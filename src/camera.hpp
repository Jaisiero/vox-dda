#pragma once

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtx/quaternion.hpp>
#include <daxa/daxa.hpp>

using namespace daxa::types;

const glm::vec3 INIT_FORWARD = {0, 0, 1};
const glm::vec3 INIT_CAMERA_POS = {0, 0, -5.0};
const glm::vec3 INIT_CAMERA_UP = {0, 1, 0};

const f32 INIT_CAMERA_FOV = 90.0f;
const f32 INIT_CAMERA_WIDTH = 800.0f;
const f32 INIT_CAMERA_HEIGHT = 600.0f;
const f32 INIT_CAMERA_NEAR = 0.001f;
const f32 INIT_CAMERA_FAR = 1000.0f;
const f32 CAMERA_SPEED = 0.1f;
const f32 MOUSE_SENSITIVITY = 0.005f;
const f32 SPEED_UP_MULTIPLIER = 10.0f;
const f32 CAMERA_DEF_FOCUS_DIST_MIN = 0.0f;
const f32 CAMERA_DEF_FOCUS_DIST_MAX = 100.0f;
const f32 CAMERA_DEF_FOCUS_ANGLE_MIN = 0.0f;
const f32 CAMERA_DEF_FOCUS_ANGLE_MAX = 5.0f;

const u32 TRIPPLE_BUFFER = 3;

inline daxa_f32mat4x4 daxa_mat4_from_glm_mat4(glm::mat4 const& m)
{
    return {
        m[0][0], m[0][1], m[0][2], m[0][3],
        m[1][0], m[1][1], m[1][2], m[1][3],
        m[2][0], m[2][1], m[2][2], m[2][3],
        m[3][0], m[3][1], m[3][2], m[3][3]
    };
}

struct Camera {
    glm::vec3 forward;
    glm::vec3 position;
    glm::vec3 center;
    glm::vec3 up;
    f32 fov;
    u32 width;
    u32 height;
    f32 _near;
    f32 _far;
    glm::vec2 last_mouse_pos;
    f32 speed;
    bool mouse_left_press;
    bool mouse_middle_pressed;
    std::array<bool, TRIPPLE_BUFFER> moved;
    u32 frame_index;
    bool shift_status;
    f32 defocus_angle;
    f32 focus_dist;

    Camera() {
        reset_camera();
    }
    
    void reset_camera() {
        forward = INIT_FORWARD;
        position = INIT_CAMERA_POS;
        up = INIT_CAMERA_UP;
        fov = INIT_CAMERA_FOV;
        width = INIT_CAMERA_WIDTH;
        height = INIT_CAMERA_HEIGHT;
        _near = INIT_CAMERA_NEAR;
        _far = INIT_CAMERA_FAR;
        speed = CAMERA_SPEED;
        last_mouse_pos = glm::vec2(0, 0);
        mouse_left_press = false;
        mouse_middle_pressed = false;
        moved[0] = moved[1] = moved[2] = true;
        frame_index = 0;
        shift_status = false;
        defocus_angle = CAMERA_DEF_FOCUS_ANGLE_MIN;
        focus_dist = CAMERA_DEF_FOCUS_DIST_MIN;
    }

    glm::mat4 _get_inverse_projection_matrix(bool flip_Y = false) {
        return glm::inverse(_get_projection_matrix(flip_Y));
    }

    glm::mat4 _get_inverse_view_projection_matrix(bool flip_Y = false) {
        return glm::inverse(_get_view_projection_matrix(flip_Y));
    }

    daxa_f32mat4x4 get_view_matrix() {
        return daxa_mat4_from_glm_mat4(_get_view_matrix());
    }

    daxa_f32mat4x4 get_projection_matrix(bool flip_Y = false) {
        return daxa_mat4_from_glm_mat4(_get_projection_matrix(flip_Y));
    }

    daxa_f32mat4x4 get_view_projection_matrix(bool flip_Y = false) {
        return daxa_mat4_from_glm_mat4(_get_view_projection_matrix(flip_Y));
    }

    daxa_f32mat4x4 get_inverse_view_matrix() {
        return daxa_mat4_from_glm_mat4(_get_inverse_view_matrix());
    }

    daxa_f32mat4x4 get_inverse_projection_matrix(bool flip_Y = false) {
        return daxa_mat4_from_glm_mat4(_get_inverse_projection_matrix(flip_Y));
    }

    daxa_f32mat4x4 get_inverse_view_projection_matrix(bool flip_Y = false) {
        return daxa_mat4_from_glm_mat4(_get_inverse_view_projection_matrix(flip_Y));
    }

    glm::vec3 camera_get_direction() {
        return forward;
    }

    glm::vec3 camera_get_right() {
        return glm::normalize(glm::cross(camera_get_direction(), up));
    }

    glm::vec3 camera_get_up() {
        return glm::normalize(glm::cross(camera_get_right(), camera_get_direction()));
    }

    glm::vec3& camera_get_position() {
        return position;
    }

    glm::vec3& camera_get_center() {
        return center;
    }

    glm::vec3& camera_get_up_vector() {
        return up;
    }

    f32& camera_get_fov() {
        return fov;
    }

    f32 camera_get_aspect() {
        return width / height;
    }

    u32& camera_get_width() {
        return width;
    }

    u32& camera_get_height() {
        return height;
    }

    f32& camera_get__near() {
        return _near;
    }

    f32& camera_get_far() {
        return _far;
    }

    f32& camera_get_speed() {
        return speed;
    }

    bool& camera_get_moved() {
        return moved[frame_index];
    }

    glm::vec2& camera_get_last_mouse_pos() {
        return last_mouse_pos;
    }

    bool& camera_get_mouse_left_press() {
        return mouse_left_press;
    }

    bool& camera_get_mouse_middle_pressed() {
        return mouse_middle_pressed;
    }

    bool& camera_get_shift_status() {
        return shift_status;
    }

    f32& camera_get_defocus_angle() {
        return defocus_angle;
    }

    f32& camera_get_focus_dist() {
        return focus_dist;
    }





    void move_camera(const glm::vec3 direction) {
        position += direction * speed * (shift_status ? SPEED_UP_MULTIPLIER : 1.0f);
        moved[0] = moved[1] = moved[2] = true;
    }

    void move_camera_forward() {
        move_camera( camera_get_direction());
    }

    void move_camera_backward() {
        move_camera(-camera_get_direction());
    }

    void move_camera_right() {
        move_camera( camera_get_right());
    }

    void move_camera_left() {
        move_camera(-camera_get_right());
    }

    void move_camera_up() {
        move_camera(camera_get_up());
    }

    void move_camera_down() {
        move_camera(-camera_get_up());
    }

    void camera_set_position(const glm::vec3 pos) {
        position = pos;
    }

    void camera_set_center(const glm::vec3 cent) {
        center = cent;
    }

    void camera_set_up_vector(const glm::vec3 up_vector) {
        up = up_vector;
    }

    void camera_set_fov(f32 fov) {
        fov = fov;
    }

    void camera_set_aspect(u32 width, u32 height) {
        width = width;
        height = height;
    }

    void camera_set_near(f32 near_plane) {
        _near = near_plane;
    }

    void camera_set_far(f32 far_plane) {
        _far = far_plane;
    }

    void camera_shift_pressed() {
        shift_status = true;
    }

    void camera_shift_released() {
        shift_status = false;
    }

    void camera_set_speed(f32 speed) {
        speed = speed;
    }

    void camera_set_moved() {
        moved[0] = moved[1] = moved[2] = true;
    }

    void camera_reset_moved() {
        moved[frame_index] = false;
        frame_index = (frame_index + 1) % TRIPPLE_BUFFER;
    }

    void camera_set_last_mouse_pos(const glm::vec2 mouse_pos) {
        last_mouse_pos = mouse_pos;
    }

    void camera_set_mouse_left_press(bool mouse_left_press) {
        mouse_left_press = mouse_left_press;
    }

    void camera_set_mouse_middle_pressed(bool mouse_middle_pressed) {
        mouse_middle_pressed = mouse_middle_pressed;
    }

    void camera_set_defocus_angle(f32 defocus_angle) {
        defocus_angle = std::max(CAMERA_DEF_FOCUS_ANGLE_MIN, std::min(CAMERA_DEF_FOCUS_ANGLE_MAX, defocus_angle));
    }

    void camera_set_focus_dist(f32 focus_dist) {
        focus_dist = std::max(CAMERA_DEF_FOCUS_DIST_MIN, std::min(CAMERA_DEF_FOCUS_DIST_MAX, focus_dist));
    }

    // rotate camera around its center
    void rotate_camera(f32 currentX, f32 currentY)
    {
        glm::vec3 up_direction = glm::vec3(0.0f, 1.0f, 0.0f);
        glm::vec3 right_direction = glm::cross(forward, up_direction);

        // check if last mouse position is set
        if (last_mouse_pos.x == 0.0f && last_mouse_pos.y == 0.0f)
        {
            camera_set_last_mouse_pos(glm::vec2(currentX, currentY));
            return;
        }

        // Calculate the change in mouse position
        f32 deltaX = (currentX - last_mouse_pos.x);
        f32 deltaY = (currentY - last_mouse_pos.y);


        camera_set_last_mouse_pos(glm::vec2(currentX, currentY));


        // Rotation
        if (deltaX != 0.0f || deltaY != 0.0f)
        {
            f32 pitch_delta = deltaY * MOUSE_SENSITIVITY;
            f32 yaw_delta = deltaX * MOUSE_SENSITIVITY;

            glm::quat q = glm::normalize(glm::cross(glm::angleAxis(-pitch_delta, right_direction),
                glm::angleAxis(-yaw_delta, glm::vec3(0.f, 1.0f, 0.0f))));
            forward = glm::rotate(q, forward);

            camera_set_moved();
        }
    }

    void rotate_camera_yaw(f32 yaw) {
        rotate_camera(yaw, 0.0f);
    }

    void rotate_camera_pitch(f32 pitch) {
        rotate_camera(0.0f, pitch);
    }

    void camera_set_mouse_delta(const glm::vec2& mouse_delta) {
        if(mouse_left_press) {
            rotate_camera(mouse_delta.x, mouse_delta.y);
        }
    }


private:
    glm::mat4 _get_view_matrix() {
        return glm::lookAt(position, position + forward, up);
    }

    glm::mat4 _get_projection_matrix(bool flip_Y = false) {
        auto proj_mat = glm::perspectiveRH_ZO(fov, width / (f32)height , _near, _far);
        if(flip_Y) 
            proj_mat[1][1] *= -1;
        return proj_mat;
    }

    glm::mat4 _get_view_projection_matrix(bool flip_Y = false) {
        return _get_projection_matrix(flip_Y) * _get_view_matrix();
    }

    glm::mat4 _get_inverse_view_matrix() {
        return glm::inverse(_get_view_matrix());
    }
};