#include "window.hpp"
#include "shared.inl"
#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>

#define SHADER_LANG_SLANG 1

static daxa::u32 size_x = 860;
static daxa::u32 size_y = 640;

int main(int argc, char const *argv[])
{
    // Create a window
    auto window = AppWindow("VOX DDA", size_x, size_y);

    daxa::Instance instance = daxa::create_instance({});

    daxa::DeviceInfo2 device_info = {.name = "my device"};
    
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
        .name = "my swapchain",
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
        .name = "my pipeline manager",
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
            .name = "my pipeline",
        });
        if (result.is_err())
        {
            std::cerr << result.message() << std::endl;
            return -1;
        }
        compute_pipeline = result.value();
    }

    daxa::TaskImage task_swapchain_image = {{.swapchain_image = true, .name = "swapchain image"}};

    daxa::TaskGraph task_graph = daxa::TaskGraph({
        .device = device,
        .swapchain = swapchain,
        .name = "my task graph",
    });
    {
        task_graph.use_persistent_image(task_swapchain_image);

        task_graph.add_task({
            .attachments = {
                daxa::inl_attachment(daxa::TaskImageAccess::COMPUTE_SHADER_STORAGE_READ_WRITE, task_swapchain_image),
            },
            .task = [compute_pipeline, task_swapchain_image](daxa::TaskInterface ti)
            {
                auto p = ComputePush{
                    .res = {size_x, size_y},
                    .image_id = ti.get(task_swapchain_image).ids[0].default_view(),    
                };
                ti.recorder.set_pipeline(*compute_pipeline);
                ti.recorder.push_constant(p);
                ti.recorder.dispatch({.x = size_x / 8, .y = size_y / 4, .z = 1});
            },
            .name = ("compute task"),
        });
        task_graph.submit({});
        task_graph.present({});
        task_graph.complete({});
    };

    while (!window.should_close()){
        window.update();
        pipeline_manager.reload_all();

        auto swapchain_image = swapchain.acquire_next_image();
        task_swapchain_image.set_images({.images = std::array{swapchain_image}});
        if (swapchain_image.is_empty())
        {
            break;
        }

        // So, now all we need to do is execute our task graph!
        task_graph.execute({});
    }
    device.wait_idle();
    device.collect_garbage();

    return 0;
}