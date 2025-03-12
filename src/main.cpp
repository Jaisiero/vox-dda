#include "window.hpp"
#include "shared.inl"
#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>
#include <random>
#include <cmath>


#define SHADER_LANG_SLANG 1

constexpr auto size_x = 860u;
constexpr auto size_y = 640u;
constexpr auto fov = 90.0f;
constexpr auto camera_pos = daxa_f32vec3{0.0f, 0.0f, -50.0f};

static void generate_voxels(u32 *voxels, u32 dim)
{
    std::random_device dev;
    std::mt19937 rng(dev());
    std::uniform_int_distribution<std::mt19937::result_type> dist(0, 1);

    for (u32 z = 0; z < dim; ++z)
    {
        for (u32 y = 0; y < dim; ++y)
        {
            for (u32 x = 0; x < dim; ++x)
            {
                const auto i = z * dim * dim + y * dim + x;
                const auto index = i >> 5;
                const auto bit = i & 31;
                // fill every bit one by one
                voxels[index] |= dist(rng) << bit;
            }
        }
    }
}

int main(int argc, char const *argv[])
{
    // Create a window
    auto window = AppWindow("VOX DDA", size_x, size_y);

    daxa::Instance instance = daxa::create_instance({});

    daxa::DeviceInfo2 device_info = {.name = "device"};
    
    daxa::Device device = instance.create_device_2(instance.choose_device({}, device_info));

    daxa::Swapchain swapchain = device.create_swapchain({
        // this handle is given by the windowing API
        .native_window = window.get_native_handle(),
        // The platform would also be retrieved from the windowing API,
        // or by hard-coding it depending on the OS.
        .native_window_platform = window.get_native_platform(),
        // Here we can supply a user-defined surface format selection
        // function, to rate formats. If you don't care what format the
        // swapchain images are in, then you can just omit this argument
        // because it defaults to `daxa::default_format_score(...)`
        .surface_format_selector = [](daxa::Format format)
        {
            switch (format)
            {
            case daxa::Format::R8G8B8A8_UINT: return 100;
            default: return daxa::default_format_score(format);
            }
        },
        .present_mode = daxa::PresentMode::MAILBOX,
        .image_usage = daxa::ImageUsageFlagBits::TRANSFER_DST | daxa::ImageUsageFlagBits::SHADER_STORAGE,
        .name = "swapchain",
    });

    auto pipeline_manager = daxa::PipelineManager({
        .device = device,
        .shader_compile_options = {
            .root_paths = {
                DAXA_SHADER_INCLUDE_DIR,
                "src/",
            },
#if defined(SHADER_LANG_SLANG)
            .language = daxa::ShaderLanguage::SLANG,
#else 
            .language = daxa::ShaderLanguage::GLSL,
#endif
            .enable_debug_info = true,
        },
        .name = "pipeline manager",
    });

    // clang-format off
    std::shared_ptr<daxa::ComputePipeline> compute_pipeline;
    {
        auto result = pipeline_manager.add_compute_pipeline({
            .shader_info = {
#if defined(SHADER_LANG_SLANG)                
                .source = daxa::ShaderFile{"compute.slang"}, 
                .compile_options = {
                    .entry_point = "entry_compute_shader",
                },
#else
                .source = daxa::ShaderFile{"compute.glsl"},
#endif
            },
            .push_constant_size = sizeof(ComputePush),
            .name = "compute pipeline",
        });
        if (result.is_err())
        {
            std::cerr << result.message() << std::endl;
            return -1;
        }
        compute_pipeline = result.value();
    }

    auto const voxel_dim = 8;
    auto const voxel_size = voxel_dim * voxel_dim * voxel_dim; 
    auto const voxel_buffer_size = voxel_size / sizeof(u32);

    u64 frame_count = 0;

    auto voxel_buffer = device.create_buffer({
        .size = voxel_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::DEDICATED_MEMORY,
        .name = "voxel buffer",
    });

    auto camera_buffer = device.create_buffer({
        .size = sizeof(CameraView),
        .allocate_info = daxa::MemoryFlagBits::DEDICATED_MEMORY,
        .name = "camera buffer",
    });

    daxa::TaskImage task_swapchain_image = {{.swapchain_image = true, .name = "swapchain image"}};
    daxa::TaskBuffer task_voxel_buffer = {{.initial_buffers = {.buffers = std::array{voxel_buffer}}, .name = "voxel buffer"}};
    daxa::TaskBuffer task_camera_buffer = {{.initial_buffers = {.buffers = std::array{camera_buffer}}, .name = "camera buffer"}};

    auto task_graph_upload = daxa::TaskGraph({
        .device = device,
        .name = "task graph upload",
    });

    {
        task_graph_upload.use_persistent_buffer(task_voxel_buffer);

        task_graph_upload.add_task({
            .attachments = {
                daxa::inl_attachment(daxa::TaskBufferAccess::TRANSFER_WRITE, task_voxel_buffer),
            },
            .task = [task_voxel_buffer](daxa::TaskInterface ti)
            {
                auto staging = ti.allocator->allocate(voxel_buffer_size).value();
                generate_voxels(reinterpret_cast<u32*>(staging.host_address), voxel_dim);
                ti.recorder.copy_buffer_to_buffer({
                    .src_buffer = ti.allocator->buffer(),
                    .dst_buffer = ti.get(task_voxel_buffer).ids[0],
                    .size = staging.size,
                });
            },
            .name = "upload task",
        });
        task_graph_upload.submit({});
        task_graph_upload.complete({});
    }
    task_graph_upload.execute({});


    auto task_graph = daxa::TaskGraph({
        .device = device,
        .swapchain = swapchain,
        .name = "task graph loop",
    });
    {
        task_graph.use_persistent_image(task_swapchain_image);
        task_graph.use_persistent_buffer(task_voxel_buffer);
        task_graph.use_persistent_buffer(task_camera_buffer);

        auto& camera = window.camera;

        task_graph.add_task({
            .attachments = {
                daxa::inl_attachment(daxa::TaskBufferAccess::TRANSFER_WRITE, task_camera_buffer),
            },
            .task = [&window, task_camera_buffer, &camera](daxa::TaskInterface ti)
            {
                const auto width = window.width;
                const auto height = window.height;
                camera.camera_set_aspect(width, height);
                auto staging = ti.allocator->allocate(sizeof(CameraView)).value();
                *reinterpret_cast<CameraView*>(staging.host_address) = {camera.get_inverse_view_matrix(), camera.get_inverse_projection_matrix(true)};
                ti.recorder.copy_buffer_to_buffer({
                    .src_buffer = ti.allocator->buffer(),
                    .dst_buffer = ti.get(task_camera_buffer).ids[0],
                    .size = staging.size,
                });
            },
            .name = "upload camera task",
        });

        task_graph.add_task({
            .attachments = {
                daxa::inl_attachment(daxa::TaskImageAccess::COMPUTE_SHADER_STORAGE_READ_WRITE, task_swapchain_image),
                daxa::inl_attachment(daxa::TaskBufferAccess::COMPUTE_SHADER_READ, task_voxel_buffer),
                daxa::inl_attachment(daxa::TaskBufferAccess::COMPUTE_SHADER_READ, task_camera_buffer),
            },
            .task = [&window, &device, compute_pipeline, task_swapchain_image, task_voxel_buffer, task_camera_buffer, &frame_count](daxa::TaskInterface ti)
            {
                const auto width = window.width;
                const auto height = window.height;
                auto p = ComputePush{
                    .cam = device.device_address(ti.get(task_camera_buffer).ids[0]).value(),
                    .res = {width, height},
                    .frame_count = frame_count++,
                    .swapchain = ti.get(task_swapchain_image).ids[0].default_view(),   
                    .voxel_buffer = ti.get(task_voxel_buffer).ids[0], 
                };
                ti.recorder.set_pipeline(*compute_pipeline);
                ti.recorder.push_constant(p);
                ti.recorder.dispatch({.x = width / 8, .y = height / 4, .z = 1});
            },
            .name = ("compute task"),
        });
        task_graph.submit({});
        task_graph.present({});
        task_graph.complete({});
    };

    auto handle_reload_result = [&](daxa::PipelineReloadResult reload_error) -> void
    {
        if (auto error = daxa::get_if<daxa::PipelineReloadError>(&reload_error))
        {
            std::cout << "Failed to reload " << error->message << std::endl;
        }
        else if (daxa::get_if<daxa::PipelineReloadSuccess>(&reload_error))
        {
            std::cout << "Successfully reloaded!" << std::endl;
        }
    };

    while (!window.should_close()){
        window.update();
        
        if (window.swapchain_out_of_date){
            swapchain.resize();
            window.swapchain_out_of_date = false;
            std::cout << "Resized swapchain" << std::endl;
        }

        auto swapchain_image = swapchain.acquire_next_image();
        task_swapchain_image.set_images({.images = std::array{swapchain_image}});
        if (!swapchain_image.is_empty())
        {
            handle_reload_result(pipeline_manager.reload_all());
    
            // So, now all we need to do is execute our task graph!
            task_graph.execute({});
            device.collect_garbage();
        }
    }
    device.wait_idle();
    device.collect_garbage();

    device.destroy_buffer(voxel_buffer);
    device.destroy_buffer(camera_buffer);

    return 0;
}