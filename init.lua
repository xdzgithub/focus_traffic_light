-- ========== 清理区 ==========
if _G.myWindowFilter then
    _G.myWindowFilter:unsubscribeAll()
    _G.myWindowFilter = nil
end

if _G.myPendingTimer then
    _G.myPendingTimer:stop()
    _G.myPendingTimer = nil
end

-- ========== 功能代码 ==========

local fnutils = hs.fnutils
local wf = hs.window.filter

local windowFilter = wf.default  -- 使用默认 filter

-- 记录最近一个正常前台窗口
local lastRealWindow = nil

-- ===== 工具函数：当前 app 是否还有可见标准窗口 =====
local function appHasVisibleStandardWindow(app)
    if not app then return false end
    local wins = app:allWindows() or {}
    for _, w in ipairs(wins) do
        if w:isStandard() and w:isVisible() then
            return true
        end
    end
    return false
end

-- ===== 工具函数：聚焦同一个 app 内最近使用的窗口 =====
local function focusMostRecentWindowOfApp(app)
    if not app then return false end
    local wins = wf.default:getWindows(wf.sortByFocusedLast)
    for _, w in ipairs(wins) do
        if w:application() and w:application():pid() == app:pid() and w:isVisible() then
            w:focus()
            return true
        end
    end
    return false
end

-- ===== 检测当前是否在输入状态 =====
local function isTyping()
    local frontApp = hs.application.frontmostApplication()
    if not frontApp then return false end
    
    -- 获取当前焦点元素
    local focusedElement = hs.uielement.focusedElement()
    if not focusedElement then return false end
    
    -- 检查是否是文本输入框
    local role = focusedElement:role()
    if role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox" then
        return true
    end
    
    return false
end

-- ===== 兜底：找到并聚焦"下一个合适窗口" =====
local function findAndFocusNextWindow()
    -- 如果当前正在输入,不切换焦点
    if isTyping() then
        return
    end
    
    local mouseScreen = hs.mouse.getCurrentScreen()
    if not mouseScreen then return end

    local standardWindows = wf.default:getWindows(wf.sortByFocusedLast)

    -- 尝试在当前屏幕和空间找窗口
    for _, w in ipairs(standardWindows) do
        if w:screen() and w:screen():id() == mouseScreen:id() then
            local spaces = hs.spaces.windowSpaces(w:id())
            local currentSpace = hs.spaces.focusedSpace()

            if spaces and #spaces > 0 and currentSpace then
                for _, space in ipairs(spaces) do
                    if space == currentSpace then
                        w:focus()
                        return
                    end
                end
            end
        end
    end
    
    -- 如果没找到合适的窗口,尝试恢复到最后记录的窗口
    if lastRealWindow then
        local success = pcall(function()
            if lastRealWindow:isVisible() then
                lastRealWindow:focus()
            end
        end)
        if success then return end
    end
end

-- 延迟触发器（带防抖）
local function triggerFindNext(delay)
    if _G.myPendingTimer then
        _G.myPendingTimer:stop()
    end

    _G.myPendingTimer = hs.timer.doAfter(delay, function()
        findAndFocusNextWindow()
        _G.myPendingTimer = nil
    end)
end

-- ========== 订阅窗口事件 ==========

-- 记录最近的正常前台窗口
windowFilter:subscribe(wf.windowFocused, function(w, appName, event)
    if w then
        lastRealWindow = w
    end
end)

-- 处理窗口销毁 / 最小化 / 隐藏事件
windowFilter:subscribe({
    wf.windowDestroyed,
    wf.windowMinimized,
    wf.windowHidden,
}, function(window, appName, event)
    ----------------------------------------------------------------
    -- 微信特殊处理：如果还有微信其他窗口，强制把焦点拉回微信
    ----------------------------------------------------------------
    if appName == "WeChat" or appName == "微信" then
        hs.timer.doAfter(0.05, function()
            local app = hs.application.get(appName)
            if app and appHasVisibleStandardWindow(app) then
                app:activate(true)
                if not focusMostRecentWindowOfApp(app) then
                    app:activate(true)
                end
            else
                findAndFocusNextWindow()
            end
        end)
        return
    end

    ----------------------------------------------------------------
    -- 其他普通 app
    ----------------------------------------------------------------
    triggerFindNext(0.1)
end)

-- ========== 保存引用 ==========
_G.myWindowFilter = windowFilter
