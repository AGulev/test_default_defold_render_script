local M = {}

M.PROJ_FIXED_FIT =     hash("default_projection_fixed_fit")
M.PROJ_FIXED =         hash("default_projection_fixed")
M.PROJ_STRETCH =       hash("default_projection_stretch")
M.PROJ_WINDOW =        hash("default_projection_window")

local DEFAULT_NEAR = -1
local DEFAULT_FAR =   1
local DEFAULT_ZOOM =  1

local currently_used_projection = {}
local window_projection = {}
local current_state = {}

local cameras = {}
local projections = {}

local default_view = vmath.matrix4()

projections[M.PROJ_FIXED] = function(camera, state)
    camera.zoom = camera.zoom or DEFAULT_ZOOM
    local projected_width = state.window_width / camera.zoom
    local projected_height = state.window_height / camera.zoom
    local left = -(projected_width - state.width) / 2
    local bottom = -(projected_height - state.height) / 2
    local right = left + projected_width
    local top = bottom + projected_height
    return vmath.matrix4_orthographic(left, right, bottom, top, camera.near, camera.far)
end

projections[M.PROJ_FIXED_FIT] = function(camera, state)
    camera.zoom = math.min(state.window_width / state.width, state.window_height / state.height)
    return projections[M.PROJ_FIXED](camera, state)
end

projections[M.PROJ_STRETCH] = function(camera, state)
    return vmath.matrix4_orthographic(0, state.width, 0, state.height, camera.near, camera.far)
end

projections[M.PROJ_WINDOW] = function(camera, state)
    return vmath.matrix4_orthographic(0, state.window_width, 0, state.window_height, camera.near, camera.far)
end

local function get_camera_projection(cam)
    -- return go.get(cam, "projection")
    return M.hacky_proj
end

local function get_camera_view(cam)
    -- return go.get(cam, "view")
    return M.hacky_view
end

local function init_camera(cam, projection_fn, near, far, zoom)
    cam.near = near == nil and DEFAULT_NEAR or near
    cam.far = far == nil and DEFAULT_FAR or far
    cam.zoom = zoom == nil and DEFAULT_ZOOM or zoom
    cam.projection_fn = projection_fn
    cam.view_fn = function() return default_view end
    cam.frustum = {}
end

local function update_camera(cam, state)
    cam.proj = cam.projection_fn(cam, state)
    cam.view = cam.view_fn(cam, state)
    cam.frustum.frustum = cam.proj * cam.view
end

local function get_default_camera()
    return next(cameras) and cameras[1] or currently_used_projection
end

local function get_projection(cam)
    if projections[cam] then
        if cam == M.PROJ_WINDOW then
            return window_projection
        else
            return currently_used_projection
        end
    end
    return cam
end

M.update_state = function()
    current_state.window_width = render.get_window_width()
    current_state.window_height = render.get_window_height()
    local is_valid = current_state.window_width > 0 and current_state.window_height > 0
    if not is_valid then
        return nil
    end
    -- Make sure state updated only once when resize window
    if current_state.window_width == current_state.prev_window_width and
       current_state.window_height == current_state.prev_window_height then
        return current_state
    end
    current_state.prev_window_width = current_state.window_width
    current_state.prev_window_height = current_state.window_height
    current_state.width = render.get_width()
    current_state.height = render.get_height()
    if next(cameras) then
        for _, camera in pairs(cameras) do
            update_camera(camera, current_state)
        end
    elseif next(currently_used_projection) then
        update_camera(currently_used_projection, current_state)
    end
    if next(window_projection) then
        update_camera(window_projection, current_state)
    end
    return current_state
end

M.activate = function(cam)
    msg.post(cam, "acquire_camera_focus")
end

M.deactivate = function(cam)
    msg.post(cam, "release_camera_focus")
end

M.use = function(cam, near, far, zoom)
    if projections[cam] then
        init_camera(currently_used_projection, projections[cam], near, far, zoom)
        update_camera(currently_used_projection, current_state)
        -- window projection should be inited somewhere
        if not next(window_projection) then
            init_camera(window_projection, projections[M.PROJ_WINDOW], near, far, zoom)
            update_camera(window_projection, current_state)
        end
    else
        if type(cam) == "string" then
            cam = msg.url(cam)
        end
        M.activate(cam)
        cameras[#cameras + 1] = {id = cam, projection_fn = get_camera_projection, view_fn = get_camera_view, frustum = {}}
    end
end

M.disuse = function(cam)
    if not projections[cam] then
        if type(cam) == "string" then
            cam = msg.url(cam)
        end
        M.deactivate(cam)
        for k, _ in pairs(cameras) do
            if k == cam then
                table.remove(cameras, k)
                return
            end
        end
    end
end

M.set_render = function(cam)
    cam = get_projection(cam)
    if not cam then
        cam = get_default_camera()
        -- if it's camera component we should get projection and view.
        update_camera(cam, current_state)
    end
    render.set_view(cam.view)
    render.set_projection(cam.proj)
end

M.get_frustum = function(cam)
    cam = get_projection(cam)
    if not cam then
        cam = get_default_camera()
    end
    return cam.frustum
end

M.hacky_view = nil
M.hacky_proj = nil
M.hacky_camera_update = function(view, proj)
    M.hacky_view = view
    M.hacky_proj = proj
end

return M
