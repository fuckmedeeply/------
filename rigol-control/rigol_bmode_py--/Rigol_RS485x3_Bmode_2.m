function Rigol_RS485x3_Bmode_2()
% RIGOL示波器通讯控制脚本
% 基于HelpGUI.txt中的连接方式实现简单的连接/断开功能
% 增加三维位移控制功能
% 增加自动化功能：当示波器和三个串口连接成功后，当选择间隔位移模式并点击执行位移，
    

    % 创建图形界面 - 放大界面尺寸
    fig = uifigure('Name', '扫描成像-二维B模式', 'Position', [50, 50, 1600, 1000]);
    
    % 创建连接状态标签
    statusLabel = uilabel(fig, 'Text', '状态: 未连接', 'Position', [50, 970, 1200, 30], ...
                         'FontSize', 16, 'FontWeight', 'bold');
    
    % 固定设备地址
    deviceAddress = 'USB0::0x1AB1::0x0515::MS5A263402210::INSTR';
    
    % 创建数据保存地址选择框
    uilabel(fig, 'Text', '保存地址:', 'Position', [50, 920, 80, 30], 'FontSize', 14);
    savePathEdit = uieditfield(fig, 'text', 'Position', [130, 920, 420, 30], ...
                              'Value', 'D:\rigol_data', 'FontSize', 14);
    
    % 创建连接按钮=
    connectBtn = uibutton(fig, 'push', 'Text', '连接示波器', 'Position', [50, 870, 150, 40], ...
                         'ButtonPushedFcn', @connectCallback, 'FontSize', 14);
    
    % 创建AUTO运行/停止按钮
    runStopBtn = uibutton(fig, 'state', 'Text', 'AUTO运行', 'Position', [250, 870, 150, 40], ...
                         'ValueChangedFcn', @runStopCallback, 'Enable', 'off', 'FontSize', 14);
    
    % 创建SINGLE运行/停止按钮
    singleRunBtn = uibutton(fig, 'state', 'Text', 'SINGLE运行', 'Position', [450, 870, 150, 40], ...
                         'ValueChangedFcn', @singleRunCallback, 'Enable', 'off', 'FontSize', 14);
    
    waitPerMM = 0.5;
    preAcquireDelay = 0.5;
    % 创建采集长度输入框
    uilabel(fig, 'Text', '采集长度(点):', 'Position', [650, 920, 100, 30], 'FontSize', 14);
    pointsEdit = uieditfield(fig, 'numeric', 'Position', [750, 920, 100, 30], ...
                           'Value', 1000, 'FontSize', 14, 'Limits', [1000, 100000], 'RoundFractionalValues', 'on', ...
                           'ValueChangedFcn', @pointsEditChanged);
    
    % 创建采样率和存储深度显示标签
    samplingRateLabel = uilabel(fig, 'Text', '采样率: -- MSa/s', 'Position', [950, 920, 200, 30], 'FontSize', 14);
    memoryDepthLabel = uilabel(fig, 'Text', '存储深度: -- k点', 'Position', [1150, 920, 200, 30], 'FontSize', 14);
    
    % 创建采集数据按钮
    acquireBtn = uibutton(fig, 'push', 'Text', '采集屏幕数据', 'Position', [650, 870, 200, 40], ...
                      'ButtonPushedFcn', @acquireCallback, 'Enable', 'off', 'FontSize', 14);
                  
    % 采集长度输入框值变更回调函数
    function pointsEditChanged(~, ~)
        % 确保采集长度不超过存储深度
        if isConnected && currentMemoryDepth > 0 && pointsEdit.Value > currentMemoryDepth
            pointsEdit.Value = currentMemoryDepth;
            uialert(fig, ['采集长度不能超过存储深度(' num2str(currentMemoryDepth/1000) 'k点)'], '警告', 'Icon', 'warning');
        end
    end
    
    % 位移模式切换回调函数
    function moveModeChanged(~, event)
        if event.NewValue == continuousBtn
            % 切换到持续位移模式
            isContinuousMode = true;
            movementMode = 1;  % 关键：设置为持续位移模式
            stepDistanceEdit.Enable = 'off';
            % 获取当前状态并添加新行
            currentStatus = statusBox.Value;
            newMessage = '已切换到持续位移模式';
            if ischar(currentStatus)
                % 如果是字符串，直接添加新行
                statusBox.Value = [currentStatus; newMessage];
            elseif iscell(currentStatus) || isstring(currentStatus)
                % 如果是元胞数组或字符串数组，添加到数组中
                statusBox.Value = [currentStatus; newMessage];
            else
                % 其他情况，转换为字符串后设置
                statusBox.Value = {'位移状态: 未连接'; newMessage};
            end
        else
            % 切换到间断位移模式
            isContinuousMode = false;
            movementMode = 2;  % 关键：设置为间隔位移模式
            stepDistanceEdit.Enable = 'on';
            stepDistance = stepDistanceEdit.Value;
            intervalDistance = stepDistance;  % 关键：同步更新间隔距离
            % 获取当前状态并添加新行
            currentStatus = statusBox.Value;
            newMessage = sprintf('已切换到间断位移模式，间隔距离: %.2f mm', stepDistance);
            if ischar(currentStatus)
                % 如果是字符串，直接添加新行
                statusBox.Value = [currentStatus; newMessage];
            elseif iscell(currentStatus) || isstring(currentStatus)
                % 如果是元胞数组或字符串数组，添加到数组中
                statusBox.Value = [currentStatus; newMessage];
            else
                % 其他情况，转换为字符串后设置
                statusBox.Value = {'位移状态: 未连接'; newMessage};
            end
        end
    end
    
    % 创建三维位移控制面板 - 扩大面板尺寸
    positionPanel = uipanel(fig, 'Title', '三维位移控制', 'Position', [1150, 50, 400, 800], 'FontSize', 14);
    
    % 固定串口列表（不再扫描）
    availablePorts = {'COM20','COM21','COM22'};
    
    % 创建串口连接按钮
    % 缩小“连接串口”按钮宽度
    serialConnBtn = uibutton(positionPanel, 'state', 'Text', '连接串口', 'Position', [20, 280, 210, 30], ...
                          'ValueChangedFcn', @serialConnectCallback, 'FontSize', 12);
    
    % 创建初始化按钮
    % 缩小“初始化系统”按钮宽度
    initBtn = uibutton(positionPanel, 'push', 'Text', '初始化系统', 'Position', [260, 280, 210, 30], ...
                     'ButtonPushedFcn', @initializeSystem, 'Enable', 'off', 'FontSize', 12);
    
    % 创建执行位移按钮
    % 缩小“执行位移”按钮宽度
    moveBtn = uibutton(positionPanel, 'push', 'Text', '执行位移', 'Position', [20, 240, 210, 30], ...
                     'ButtonPushedFcn', @executeMovement, 'Enable', 'off', 'FontSize', 12);
    
    % 创建停止位移按钮
    % 缩小“停止位移”按钮宽度
    stopBtn = uibutton(positionPanel, 'push', 'Text', '停止位移', 'Position', [260, 240, 210, 30], ...
                     'ButtonPushedFcn', @stopMovement, 'Enable', 'off', 'FontSize', 12);

    % 创建返回起点按钮
    % 缩小“返回起点”按钮宽度
    returnBtn = uibutton(positionPanel, 'push', 'Text', '返回起点', 'Position', [20, 200, 210, 30], ...
                     'ButtonPushedFcn', @returnToOrigin, 'Enable', 'off', 'FontSize', 12);

    % 创建设置轨迹按钮
    % 缩小“设置轨迹”按钮宽度
    setTrajectoryBtn = uibutton(positionPanel, 'push', 'Text', '设置轨迹', 'Position', [260, 200, 210, 30], ...
                     'ButtonPushedFcn', @setTrajectory, 'Enable', 'off', 'FontSize', 12);

    % 位移模式选择按钮
    uilabel(positionPanel, 'Text', '位移模式:', 'Position', [20, 160, 80, 20], 'FontSize', 12);
    % 缩小“持续/间断位移”选项框宽度
    moveModeBtn = uibuttongroup(positionPanel, 'Position', [110, 160, 360, 30], ...
                              'SelectionChangedFcn', @moveModeChanged, 'FontSize', 12);
    continuousBtn = uiradiobutton(moveModeBtn, 'Text', '持续位移', 'Position', [5, 5, 120, 20], 'FontSize', 12);
    stepBtn = uiradiobutton(moveModeBtn, 'Text', '间断位移', 'Position', [150, 5, 120, 20], 'FontSize', 12);
    continuousBtn.Value = true;
    
    % 间隔距离输入框
    uilabel(positionPanel, 'Text', '间隔距离 (mm):', 'Position', [20, 130, 100, 20], 'FontSize', 12);
    stepDistanceEdit = uieditfield(positionPanel, 'numeric', 'Position', [130, 130, 100, 22], ...
                                 'Value', 0.1, 'Limits', [0.1, 100], 'Enable', 'off', 'FontSize', 12, 'ValueDisplayFormat', '%.2f', ...
                                 'ValueChangedFcn', @intervalDistanceChanged);
    
    uilabel(positionPanel, 'Text', '采前等待 (秒):', 'Position', [250, 130, 110, 20], 'FontSize', 12);
    preDelayEdit = uieditfield(positionPanel, 'numeric', 'Position', [350, 130, 100, 22], ...
                               'Value', preAcquireDelay, 'Limits', [0, 5], 'Enable', 'on', 'FontSize', 12, 'ValueDisplayFormat', '%.2f', ...
                               'ValueChangedFcn', @preDelayChanged);
    
    
    % X轴位移控制（移除滑块，仅保留标签/输入/串口）
    uilabel(positionPanel, 'Text', 'X轴位置 (mm):', 'Position', [20, 100, 100, 20], 'FontSize', 12);
    % X轴数值输入框
    xPosEdit = uieditfield(positionPanel, 'numeric', 'Position', [130, 100, 100, 22], ...
                         'Value', 0, 'Limits', [0, 400], 'ValueChangedFcn', @setXPositionFromEdit, 'FontSize', 12, 'ValueDisplayFormat', '%.2f');
    % X轴串口选择下拉菜单
    uilabel(positionPanel, 'Text', '串口:', 'Position', [300, 100, 40, 20], 'FontSize', 12);
    xPortDropdown = uidropdown(positionPanel, 'Position', [340, 100, 110, 22], ...
                             'Items', availablePorts, ...
                             'Value', 'COM20', 'FontSize', 12);
    
    % Y轴位移控制（移除滑块，仅保留标签/输入/串口）
    uilabel(positionPanel, 'Text', 'Y轴位置 (mm):', 'Position', [20, 60, 100, 20], 'FontSize', 12);
    % Y轴数值输入框
    yPosEdit = uieditfield(positionPanel, 'numeric', 'Position', [130, 60, 100, 22], ...
                         'Value', 0, 'Limits', [0, 400], 'ValueChangedFcn', @setYPositionFromEdit, 'FontSize', 12, 'ValueDisplayFormat', '%.2f');
    % Y轴串口选择下拉菜单
    uilabel(positionPanel, 'Text', '串口:', 'Position', [300, 60, 40, 20], 'FontSize', 12);
    yPortDropdown = uidropdown(positionPanel, 'Position', [340, 60, 110, 22], ...
                             'Items', availablePorts, ...
                             'Value', 'COM21', 'FontSize', 12);
    
    % Z轴位移控制（移除滑块，仅保留标签/输入/串口）
    uilabel(positionPanel, 'Text', 'Z轴位置 (mm):', 'Position', [20, 20, 100, 20], 'FontSize', 12);
    % Z轴数值输入框
    zPosEdit = uieditfield(positionPanel, 'numeric', 'Position', [130, 20, 100, 22], ...
                         'Value', 0, 'Limits', [0, 100], 'ValueChangedFcn', @setZPositionFromEdit, 'FontSize', 12, 'ValueDisplayFormat', '%.2f');
    % Z轴串口选择下拉菜单
    uilabel(positionPanel, 'Text', '串口:', 'Position', [300, 20, 40, 20], 'FontSize', 12);
    zPortDropdown = uidropdown(positionPanel, 'Position', [340, 20, 110, 22], ...
                             'Items', availablePorts, ...
                             'Value', 'COM22', 'FontSize', 12);
    
    % 位移状态显示：增大宽度，同时保持采集显示区域整体宽度不变
    statusBox = uitextarea(positionPanel, 'Position', [495, 10, 310, 300], 'FontSize', 10, ...
                         'Value', '位移状态: 未连接', 'Editable', 'off');
    
    % 间隔距离变更回调：同步更新intervalDistance
    function intervalDistanceChanged(~, ~)
        try
            intervalDistance = stepDistanceEdit.Value;
            addStatusMessage(['间隔距离设置为: ', num2str(intervalDistance), ' mm']);
        catch ME
            addStatusMessage(['更新间隔距离失败: ', ME.message]);
        end
    end
    
    function preDelayChanged(~, ~)
        try
            preAcquireDelay = preDelayEdit.Value;
            addStatusMessage(['采前等待设置为: ', num2str(preAcquireDelay), ' 秒']);
        catch ME
            addStatusMessage(['更新采前等待失败: ', ME.message]);
        end
    end
    
    % 创建采集显示区域（仅保留“采样点”波形 + 三维位移控制）
    % 缩窄采集显示区域宽度
    wavePanel = uipanel(fig, 'Title', '采集显示', 'Position', [50, 50, 900, 800], 'FontSize', 14);
    % 波形显示（仅保留“采样点”视图）
    % 同步缩小波形坐标轴宽度
    waveAxes1 = uiaxes(wavePanel, 'Position', [40, 420, 820, 350]);
    title(waveAxes1, '波形数据-采样点', 'FontSize', 14);
    xlabel(waveAxes1, '采样点', 'FontSize', 12);
    ylabel(waveAxes1, '幅值', 'FontSize', 12);
    % 将三维位移控制面板移动到采集显示区域下方
    try
        positionPanel.Parent = wavePanel;
        % 缩窄采集区域后，同步调整三维位移面板宽度
        positionPanel.Position = [40, 30, 820, 350];
    catch
        % 若移动失败则保持原位，不影响后续逻辑
    end
    % 新建B模式显示面板到右侧（矩形）
    % 增加B模式显示区域宽度，并左移以填充缩窄的采集显示区域释放的空间
    bmodePanel = uipanel(fig, 'Title', 'B模式成像', 'Position', [970, 50, 580, 800], 'FontSize', 14);
    % 同步增大B模式坐标轴宽度
    bmodeAxes = uiaxes(bmodePanel, 'Position', [20, 20, 540, 760]);
    title(bmodeAxes, '', 'FontSize', 14);
    xlabel(bmodeAxes, 'Y位置 (mm)', 'FontSize', 12);
    ylabel(bmodeAxes, '深度 (mm)', 'FontSize', 12);
    colormap(bmodeAxes, gray);
    axis(bmodeAxes, 'ij');
    cla(bmodeAxes);
    
    % 全局变量存储示波器对象
    scopeObj = [];
    isConnected = false;
    isRunning = false;
    waveformData = [];
    waveformTime = [];
    currentMemoryDepth = 0; % 当前存储深度
    currentSamplingRate = 0; % 当前采样率
    acqInfoTimer = []; % 采样率/存储深度实时刷新定时器
    scopeIoLock = false;
    lastAcqInfoErrorAt = 0;
    lastAcqInfoErrorMsg = '';
    
    % 三维位移控制相关全局变量
    % 串口设置
    comPortX = 'COM8';
    
    % 初始化位置变量
    currentXPosition = 0;
    currentYPosition = 0;
    currentZPosition = 0;
    targetXPosition = 0; % 目标X位置
    targetYPosition = 0; % 目标Y位置
    targetZPosition = 0; % 目标Z位置
    validXPosition = 0; % 有效X位置
    validYPosition = 0; % 有效Y位置
    validZPosition = 0; % 有效Z位置
    stepTargetX = 0; % 单步目标X位置
    stepTargetY = 0; % 单步目标Y位置
    stepTargetZ = 0; % 单步目标Z位置
    stepX = 0; % X轴单步位移量
    stepY = 0; % Y轴单步位移量
    stepZ = 0; % Z轴单步位移量
    totalSteps = 0; % 总步数
    serialConnected = false;
    isContinuousMode = true; % 默认为持续位移模式
    isStepMoving = false; % 是否正在进行间断位移
    stepDistance = 10; % 默认步进距离
    stepXRemaining = 0; % X轴剩余位移
    stepYRemaining = 0; % Y轴剩余位移
    stepZRemaining = 0; % Z轴剩余位移
    checkStatusTimer = []; % 用于检查示波器状态的定时器
    discreteMoving = false; % 是否正在进行间断位移
    currentStep = 0; % 当前步数
    isAutoRunning = false; % 是否处于自动运行模式

    % B模式成像相关全局变量（新增）
    bmodeImg = [];
    bmodeDepth = [];
    bmodeLateral = [];
    bmodeColCount = 0;
    globalEnvMax = 0; % 全局包络最大值，用于一致的0 dB归一化
    DR = 50;         % 显示动态范围（dB）
    contrastGain = 1.4;
    c_sound = 1540;  % 声速 (m/s)
    bmodeEnabled = true;

    % 辅助函数：采集后更新B模式图像（单列）
    function updateBModeAfterAcquisition(waveData, Fs, sampleLength, lateral_mm)
        try
            if ~bmodeEnabled
                return;
            end
            if isempty(waveData) || sampleLength <= 0 || Fs <= 0
                return;
            end
            waveData = double(waveData(:));
            waveData = waveData - mean(waveData, 'omitnan');
            env = abs(hilbert(waveData));
            env(~isfinite(env)) = 0;
            localMax = max(env);
            if ~isfinite(localMax) || localMax <= 0
                localMax = eps;
            end
            if globalEnvMax <= 0
                globalEnvMax = localMax;
            else
                globalEnvMax = max(globalEnvMax, localMax);
            end
            minDB = -DR;
            colDb = 20 * log10((env + eps) ./ globalEnvMax);
            colDb = colDb * contrastGain;
            colDb(~isfinite(colDb)) = minDB;
            colDb(colDb < minDB) = minDB;
            colDb(colDb > 0) = 0;

            % 深度轴（mm）：c/2换算，采样间隔为1/Fs
            depth_mm = (0:sampleLength-1)' * (c_sound/(2*Fs)) * 1000;

            % 累积B模式矩阵
            if isempty(bmodeImg)
                bmodeImg = colDb(:);
                bmodeDepth = depth_mm;
            else
                targetH = size(bmodeImg, 1);
                if sampleLength > targetH
                    % 截断到已有高度
                    colDb = colDb(1:targetH);
                    depth_mm = bmodeDepth;
                elseif sampleLength < targetH
                    % 低于已有高度则底部填充最小dB
                    colDb = [colDb(:); repmat(minDB, targetH - sampleLength, 1)];
                    depth_mm = bmodeDepth;
                end
                bmodeImg(:, end+1) = colDb(:);
            end
            % 更新横向位置（按当前Y位置）
            bmodeLateral = [bmodeLateral, lateral_mm];
            bmodeColCount = bmodeColCount + 1;

            % 绘制/更新图像（不使用等比缩放，避免Y轴实际长度随X扩展变化）
            imagesc(bmodeAxes, bmodeLateral, bmodeDepth, bmodeImg);
            bmodeAxes.CLim = [-DR, 0];
            bmodePanel.Title = sprintf('B模式成像 - 列=%d, DR=%d dB, 增益=%.1f', bmodeColCount, DR, contrastGain);
            bmodeAxes.YLimMode = 'auto';
            bmodeAxes.YTickMode = 'auto';
            if numel(bmodeLateral) >= 2
                xmin = min(bmodeLateral);
                xmax = max(bmodeLateral);
                span = xmax - xmin;
                if span > 0
                    tickTarget = min(16, max(6, round(6 + bmodeColCount/4)));
                    rawStep = span / tickTarget;
                    niceSteps = [0.01 0.02 0.05 0.1 0.2 0.5 1 2 5 10 20];
                    idx = find(niceSteps <= rawStep, 1, 'last');
                    if isempty(idx)
                        step = niceSteps(1);
                    else
                        step = niceSteps(idx);
                    end
                    xt = xmin:step:xmax;
                    bmodeAxes.XTickMode = 'manual';
                    bmodeAxes.XTick = xt;
                end
            end
        catch e
            addStatusMessage(['更新B模式失败: ', e.message]);
        end
    end
    
    % 从编辑框设置X轴位置
    function setXPositionFromEdit(~, ~)
        % 获取编辑框中的值并更新目标位置
        newPosition = xPosEdit.Value;
        targetXPosition = newPosition;
    end
    
    % 从编辑框设置Y轴位置
    function setYPositionFromEdit(~, ~)
        % 获取编辑框中的值并更新目标位置
        newPosition = yPosEdit.Value;
        targetYPosition = newPosition;
    end
    
    % 从编辑框设置Z轴位置
    function setZPositionFromEdit(~, ~)
        % 获取编辑框中的值并更新目标位置
        newPosition = zPosEdit.Value;
        targetZPosition = newPosition;
    end
    
    % 设置X轴位置（从滑块）
    function setXPosition(~, ~)
        % 获取编辑框值并更新目标X位置
        newPosition = xPosEdit.Value;
        targetXPosition = newPosition;
    end
    
    % 设置Y轴位置（从滑块）
    function setYPosition(~, ~)
        % 获取编辑框值并更新目标Y位置
        newPosition = yPosEdit.Value;
        targetYPosition = newPosition;
    end
    
    % 设置Z轴位置（从滑块）
    function setZPosition(~, ~)
        % 获取编辑框值并更新目标Z位置
        newPosition = zPosEdit.Value;
        targetZPosition = newPosition;
    end
    
    comPortX = 'COM20';  % X轴对应串口17
    comPortY = 'COM21';  % Y轴对应串口18
    comPortZ = 'COM22';  % Z轴对应串口19
    baudRate = 19200;
    dataBits = 8;
    parity = 'even';    % 偶校验
    stopBits = 1;       % 1个结束位
    
    % 串口对象
    serialObjX = [];
    serialObjY = [];
    serialObjZ = [];
    serialConnected = false;
    systemInitialized = false;
    
    % 位置变量
    xPosition = 0;
    yPosition = 0;
    zPosition = 0;
    currentXPosition = 0;
    currentYPosition = 0;
    currentZPosition = 0;
    validXPosition = 0;
    validYPosition = 0;
    validZPosition = 0;
    
    % 位移模式
    movementMode = 1;  % 1=持续位移, 2=间隔位移
    intervalDistance = 10;  % 默认间隔距离10mm
    isAutoRunning = false;
    checkStatusTimer = [];
    isMovementExecuting = false;
    stopRequested = false;
    trajectoryEnabled = false;
    trajectoryParams = struct('xSpan', 10, 'xStep', 1, 'yStep', 1, 'yLines', 10, 'resetBmode', true, 'startAtCurrent', true, 'acquireEachPoint', true);

    function setStopButtonEnabled(enabled)
        if enabled
            stopBtn.Enable = 'on';
        else
            stopBtn.Enable = 'off';
        end
    end

    function setAuxButtonsEnabled(enabled)
        if enabled
            returnBtn.Enable = 'on';
            setTrajectoryBtn.Enable = 'on';
        else
            returnBtn.Enable = 'off';
            setTrajectoryBtn.Enable = 'off';
        end
    end

    function stopped = waitInterruptible(secondsToWait)
        stopped = false;
        if secondsToWait <= 0
            drawnow;
            return;
        end
        t0 = tic;
        while toc(t0) < secondsToWait
            if stopRequested
                stopped = true;
                return;
            end
            pause(0.05);
            drawnow;
        end
    end
    
    % 连接示波器回调函数
    function connectCallback(~, ~)
        try
            if isConnected && ~isempty(scopeObj)
                % 断开连接
                fclose(scopeObj);
                delete(scopeObj);
                scopeObj = [];
                
                % 更新界面状态
                statusLabel.Text = '状态: 已断开连接';
                statusLabel.FontColor = [0, 0, 0]; % 黑色
                connectBtn.Text = '连接示波器';
                runStopBtn.Enable = 'off'; % 禁用运行/停止按钮
                runStopBtn.Value = false;
                runStopBtn.Text = 'AUTO运行';
                runStopBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                singleRunBtn.Enable = 'off'; % 禁用SINGLE运行按钮
                singleRunBtn.Value = false;
                singleRunBtn.Text = 'SINGLE运行';
                singleRunBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                acquireBtn.Enable = 'off'; % 禁用采集按钮
                isConnected = false;
                isRunning = false;

                % 停止并清理实时刷新定时器
                stopAcqInfoTimer();
                
                fprintf('已断开与示波器的连接\n');
                
            else
                % 连接示波器
                % 创建VISA对象
                scopeObj = visa('ni', deviceAddress);
                
                % 设置缓冲区大小
                scopeObj.InputBufferSize = 1000000;
                scopeObj.OutputBufferSize = 1000000;
                
                % 设置超时时间
                scopeObj.Timeout = 10;
                
                % 打开连接
                fopen(scopeObj);
                
                % 发送标识查询命令
                fprintf(scopeObj, '*IDN?');
                idn = fscanf(scopeObj);
                
                % 检查是否成功连接
                if contains(idn, 'RIGOL')
                    % 更新界面状态
                    statusLabel.Text = ['状态: 已连接 - ' strtrim(idn)];
                    statusLabel.FontColor = [0, 0.7, 0]; % 绿色
                    connectBtn.Text = '断开连接';
                    runStopBtn.Enable = 'on'; % 启用运行/停止按钮
                    singleRunBtn.Enable = 'on'; % 启用SINGLE运行按钮
                    acquireBtn.Enable = 'on'; % 启用采集按钮
                    isConnected = true;
                    
                    % 获取当前存储深度
                    fprintf(scopeObj, ':ACQuire:MDEPth?');
                    mdepthStr = fscanf(scopeObj);
                    if contains(mdepthStr, 'AUTO')
                        currentMemoryDepth = 8000000; % 默认值
                    else
                        currentMemoryDepth = str2double(mdepthStr);
                    end
                    memoryDepthLabel.Text = ['存储深度: ' num2str(currentMemoryDepth/1000) ' k点'];
                    
                    % 获取当前采样率
                    fprintf(scopeObj, ':ACQuire:SRATe?');
                    srateStr = fscanf(scopeObj);
                    currentSamplingRate = str2double(srateStr);
                    samplingRateLabel.Text = ['采样率: ' num2str(currentSamplingRate/1000000) ' MSa/s'];
                    
                    fprintf('已连接到示波器: %s\n', strtrim(idn));

                    % 启动实时刷新采样率/存储深度的定时器
                    startAcqInfoTimer();
                else
                    % 连接失败，清理资源
                    fclose(scopeObj);
                    delete(scopeObj);
                    scopeObj = [];
                    uialert(fig, '无法识别RIGOL示波器，请检查连接', '连接错误');
                end
            end
        catch ME
            if ~isempty(scopeObj)
                try
                    fclose(scopeObj);
                    delete(scopeObj);
                catch
                end
                scopeObj = [];
            end
            uialert(fig, ['连接示波器失败: ' ME.message], '连接错误');
            fprintf('连接示波器失败: %s\n', ME.message);
        end
    end

    function runStopCallback(~, ~)
        if ~isConnected || isempty(scopeObj)
            return;
        end
        
        try
            if runStopBtn.Value
                % 如果SINGLE运行按钮处于激活状态，先将其关闭
                if singleRunBtn.Value
                    singleRunBtn.Value = false;
                    singleRunBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                end
                
                % 发送运行命令
                fprintf(scopeObj, ':RUN');
                runStopBtn.Text = '停止';
                runStopBtn.BackgroundColor = [1, 0.6, 0.6]; % 浅红色
                isRunning = true;
                fprintf('示波器开始AUTO运行\n');
            else
                % 发送停止命令
                fprintf(scopeObj, ':STOP');
                runStopBtn.Text = 'AUTO运行';
                runStopBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                isRunning = false;
                fprintf('示波器停止运行\n');
            end
        catch ME
            fprintf('发送运行/停止命令失败: %s\n', ME.message);
            % 重置按钮状态
            runStopBtn.Value = isRunning;
            if isRunning
                runStopBtn.Text = '停止';
                runStopBtn.BackgroundColor = [1, 0.6, 0.6];
            else
                runStopBtn.Text = 'AUTO运行';
                runStopBtn.BackgroundColor = [0.96, 0.96, 0.96];
            end
        end
    end

    % 启动采样率/存储深度实时刷新定时器
    function startAcqInfoTimer()
        try
            % 若已存在，先停止
            stopAcqInfoTimer();
            acqInfoTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 1.0, ...
                                 'TimerFcn', @refreshAcqInfo);
            start(acqInfoTimer);
        catch ME
            fprintf('启动刷新定时器失败: %s\n', ME.message);
        end
    end

    % 停止采样率/存储深度实时刷新定时器
    function stopAcqInfoTimer()
        try
            if ~isempty(acqInfoTimer) && isvalid(acqInfoTimer)
                stop(acqInfoTimer);
                delete(acqInfoTimer);
            end
        catch
        end
        acqInfoTimer = [];
    end

    % 定时查询采样率与存储深度并刷新到界面
    function refreshAcqInfo(~, ~)
        if ~isConnected || isempty(scopeObj)
            return;
        end
        if scopeIoLock
            return;
        end
        try
            scopeIoLock = true;
            cleanupLock = onCleanup(@() setScopeIoLock(false));
            if ismethod(scopeObj, 'flushinput')
                flushinput(scopeObj);
            end

            % 查询存储深度
            fprintf(scopeObj, ':ACQuire:MDEPth?');
            mdepthStr = strtrim(fscanf(scopeObj));
            if contains(upper(mdepthStr), 'AUTO')
                % AUTO 模式下设备会自动选择；保留上次/默认值
                % 可选择使用上次的 currentMemoryDepth 不变
            else
                md = str2double(mdepthStr);
                if ~isnan(md) && md > 0
                    currentMemoryDepth = md;
                    memoryDepthLabel.Text = ['存储深度: ' num2str(currentMemoryDepth/1000) ' k点'];
                    % 动态限制采集长度上限
                    pointsEdit.Limits = [pointsEdit.Limits(1), max(pointsEdit.Limits(1), currentMemoryDepth)];
                    % 如当前值超过上限则回退
                    if pointsEdit.Value > currentMemoryDepth
                        pointsEdit.Value = currentMemoryDepth;
                    end
                end
            end

            % 查询采样率
            fprintf(scopeObj, ':ACQuire:SRATe?');
            srateStr = strtrim(fscanf(scopeObj));
            sr = str2double(srateStr);
            if ~isnan(sr) && sr > 0
                currentSamplingRate = sr;
                samplingRateLabel.Text = ['采样率: ' num2str(currentSamplingRate/1000000) ' MSa/s'];
            end
        catch ME
            nowT = now;
            if ~strcmp(lastAcqInfoErrorMsg, ME.message) || (nowT - lastAcqInfoErrorAt) * 86400 > 2
                fprintf('刷新采样率/存储深度失败: %s\n', ME.message);
                lastAcqInfoErrorAt = nowT;
                lastAcqInfoErrorMsg = ME.message;
            end
            scopeIoLock = false;
        end
    end

    function setScopeIoLock(val)
        scopeIoLock = logical(val);
    end
    
    function singleRunCallback(~, ~)
        if ~isConnected || isempty(scopeObj)
            return;
        end
        
        try
            if singleRunBtn.Value
                % 如果AUTO运行按钮处于激活状态，先将其关闭
                if runStopBtn.Value
                    runStopBtn.Value = false;
                    runStopBtn.Text = 'AUTO运行';
                    runStopBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                    isRunning = false;
                end
                
                % 发送SINGLE触发命令
                fprintf(scopeObj, ':TRIGger:SWEep SINGle');
                singleRunBtn.Text = '停止';
                singleRunBtn.BackgroundColor = [0.6, 0.8, 1]; % 浅蓝色
                fprintf('示波器设置为SINGLE触发模式\n');
            else
                % 发送停止命令
                fprintf(scopeObj, ':STOP');
                singleRunBtn.Text = 'SINGLE运行';
                singleRunBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
                fprintf('示波器停止SINGLE触发模式\n');
            end
        catch ME
            fprintf('发送SINGLE触发命令失败: %s\n', ME.message);
            % 重置按钮状态
            singleRunBtn.Value = false;
            singleRunBtn.Text = 'SINGLE运行';
            singleRunBtn.BackgroundColor = [0.96, 0.96, 0.96]; % 默认颜色
        end
    end
    
    % 采集数据回调函数
    function acquireCallback(~, ~)
        if ~isConnected || isempty(scopeObj)
            uialert(fig, '请先连接示波器', '错误');
            return;
        end
        
        try
            % MAX 模式读取流程：SOUR CH1 -> MODE MAX -> FORM BYTE -> POINts <设定>
            fprintf(scopeObj, ':WAVeform:SOURce CHANnel1');
            fprintf(scopeObj, ':WAVeform:MODE MAXimum');
            fprintf(scopeObj, ':WAVeform:FORMat BYTE');

            % 读取界面设置的采集点数
            acquirePoints = max(1, round(pointsEdit.Value));
            if isnan(acquirePoints)
                acquirePoints = 1000;
            end

            % 运行状态下MAX返回屏幕数据；当设定点数超过屏幕有效点数时，使用单次采集以读取内存
            fprintf(scopeObj, ':TRIGger:STATus?');
            trigStatus = strtrim(fscanf(scopeObj));
            if acquirePoints > 1000
                if contains(upper(trigStatus), 'RUN')
                    fprintf(scopeObj, ':TRIGger:SWEep SINGle');
                    tStart = tic;
                    while toc(tStart) < 3
                        fprintf(scopeObj, ':TRIGger:STATus?');
                        ts = strtrim(fscanf(scopeObj));
                        if ~contains(upper(ts), 'RUN')
                            break;
                        end
                        pause(0.05);
                    end
                end
                fprintf(scopeObj, ':STOP');
            end

            % 按界面设定点数采集
            fprintf(scopeObj, sprintf(':WAVeform:POINts %d', acquirePoints));
            
            % 获取波形参数
            fprintf(scopeObj, ':WAVeform:PREamble?');
            preamble = str2num(fscanf(scopeObj)); %#ok<ST2NM>
            
            % 解析波形参数
            format = preamble(1);
            type = preamble(2);
            points = preamble(3);
            count = preamble(4);
            xincrement = preamble(5);
            xorigin = preamble(6);
            xreference = preamble(7);
            yincrement = preamble(8);
            yorigin = preamble(9);
            yreference = preamble(10);
            
            % 获取波形数据
            fprintf(scopeObj, ':WAVeform:DATA?');
            [data, ~] = fread(scopeObj, scopeObj.InputBufferSize);
            
            % 数据处理。读取的波形数据含有 TMC 头
            % 解析TMC头格式：#NXXXXXXX，其中N表示后面有N个字节表示数据长度
            if data(1) == '#'
                % 获取长度描述符的位数
                n_digits = str2double(char(data(2)));
                % 获取数据长度
                data_length = str2double(char(data(3:2+n_digits)'));
                % 提取有效波形数据
                data = data(2+n_digits+1:2+n_digits+data_length);
            else
                % 如果格式不符合预期，使用原来的方法
                headerLength = find(data == 10, 1); % 查找换行符位置
                data = data(headerLength+1:end);
            end
            
            % 使用设备报告的点数作为采集长度（通常与设定点数一致），避免人为截断
            sampleLength = min(length(data), points);
            data = data(1:sampleLength);
            
            % 转换为实际电压值
            waveData = (data - yreference) * yincrement + yorigin;
            
            % 创建时间轴
            timeData = ((0:sampleLength-1) - xreference) * xincrement + xorigin;
            
            % 计算频率和周期
            Fs = 1 / xincrement;
            T = sampleLength / Fs;
            F = 1 / T;
            
            % 绘制波形（仅采样点视图）
            plot(waveAxes1, 1:sampleLength, waveData);
            % 实时更新B模式（单列）
            try
                updateBModeAfterAcquisition(waveData, Fs, sampleLength, yPosEdit.Value);
            catch ME
                addStatusMessage(['B模式更新失败: ', ME.message]);
            end
            
            % 创建数据表格（统一为列向量）
            data_table = table(timeData(:), waveData(:), 'VariableNames', {'时间(s)', '电压(V)'});
            
            % 生成文件名（带时间戳）
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            % 在文件名中加入位置信息，使用界面显示的当前位置
            filename = sprintf('波形数据_%s_X=%.2f_Y=%.2f_Z=%.2f.xlsx', timestamp, xPosEdit.Value, yPosEdit.Value, zPosEdit.Value);
            
            % 获取用户设置的保存路径
            savePath = savePathEdit.Value;
            
            % 确保保存路径存在
            if ~exist(savePath, 'dir')
                [success, msg] = mkdir(savePath);
                if ~success
                    uialert(fig, ['创建保存目录失败: ' msg], '错误');
                    return;
                end
            end
            
            % 完整的文件路径
            fullFilePath = fullfile(savePath, filename);
            
            % 保存数据到Excel文件
            % 创建元数据表格
            % 使用界面显示的当前位置数值进行保存，避免因current*未及时更新导致不一致
            posXForSave = xPosEdit.Value;
            posYForSave = yPosEdit.Value;
            posZForSave = zPosEdit.Value;

            metadata = {
                '采样率(MSa/s)', Fs/1000000;
                '请求点数(k点)', acquirePoints/1000;
                '返回点数(k点)', sampleLength/1000;
                '周期(s)', T;
                '频率(Hz)', F;
                'X位置(mm)', posXForSave;
                'Y位置(mm)', posYForSave;
                'Z位置(mm)', posZForSave;
                '', ''  % 空行
            };
            
            % 将元数据和波形数据合并到一个表格中
            metadata_table = cell2table(metadata, 'VariableNames', {'参数', '值'});
            
            % 使用writetable保存Excel文件
            writetable(metadata_table, fullFilePath, 'Sheet', '元数据');
            writetable(data_table, fullFilePath, 'Sheet', '波形数据');
            fprintf('数据已自动保存到Excel文件: %s\n', fullFilePath);
            % 不再显示确认对话框，只在状态栏更新信息
            statusLabel.Text = ['状态: 已连接 - 数据已保存到Excel文件: ' fullFilePath ];
            statusLabel.FontColor = [0, 0.7, 0]; % 绿色
            
            % 如果是间断位移模式且正在进行位移，则移动到下一个位置
            if ~isContinuousMode && isStepMoving
                % 更新状态显示
                % 获取当前状态并添加新行
                currentStatus = statusBox.Value;
                newMessage = '数据采集完成，准备移动到下一个位置...';
                if ischar(currentStatus)
                    % 如果是字符串，直接添加新行
                    statusBox.Value = [currentStatus; newMessage];
                elseif iscell(currentStatus) || isstring(currentStatus)
                    % 如果是元胞数组或字符串数组，添加到数组中
                    statusBox.Value = [currentStatus; newMessage];
                else
                    % 其他情况，转换为字符串后设置
                    statusBox.Value = {'位移状态: 未连接'; newMessage};
                end
                
                % 执行下一步位移
                moveToNextStep();
            end
            
        catch ME
            uialert(fig, ['采集数据失败: ' ME.message], '错误');
            fprintf('采集数据失败: %s\n', ME.message);
        end
    end
    
    % 移动到下一个位置的函数
    function moveToNextStep()
        try
            % 计算下一步的位移
            nextStepX = min(stepDistance, abs(stepXRemaining)) * sign(stepXRemaining);
            nextStepY = min(stepDistance, abs(stepYRemaining)) * sign(stepYRemaining);
            nextStepZ = min(stepDistance, abs(stepZRemaining)) * sign(stepZRemaining);
            
            % 更新剩余位移
            stepXRemaining = stepXRemaining - nextStepX;
            stepYRemaining = stepYRemaining - nextStepY;
            stepZRemaining = stepZRemaining - nextStepZ;
            
            % 计算下一个位置
            nextX = currentXPosition + nextStepX;
            nextY = currentYPosition + nextStepY;
            nextZ = currentZPosition + nextStepZ;
            
            % 更新状态显示
            % 获取当前状态
            currentStatus = statusBox.Value;
            % 创建新的状态信息
            newStatusInfo = {
                '移动到下一个位置:',
                sprintf('X: %.2f → %.2f (%.2f mm)', currentXPosition, nextX, nextStepX),
                sprintf('Y: %.2f → %.2f (%.2f mm)', currentYPosition, nextY, nextStepY),
                sprintf('Z: %.2f → %.2f (%.2f mm)', currentZPosition, nextZ, nextStepZ)
            };
            % 合并当前状态和新状态信息
            if ischar(currentStatus)
                % 如果是字符串，转换为元胞数组后添加新行
                statusBox.Value = [cellstr(currentStatus); newStatusInfo];
            elseif iscell(currentStatus) || isstring(currentStatus)
                % 如果是元胞数组或字符串数组，添加到数组中
                statusBox.Value = [currentStatus; newStatusInfo];
            else
                % 其他情况，直接设置新状态信息
                statusBox.Value = [{'位移状态: 未连接'}; newStatusInfo];
            end
            
            % 执行X轴位移
            if abs(nextStepX) > 0.1
                % 计算圈数（1圈 = 10mm）
                circles = nextStepX / 10;
                
                % 生成电机命令
                cmd = generate_motor_command(circles);
                
                % 发送命令到X轴
                sendHexCommand(xSerialPort, cmd);
                fprintf('X轴位移命令已发送，位移量: %.2f mm\n', nextStepX);
                
                % 发送使能命令
                enableCmd = hexString2Bytes('01 06 31 00 00 01 46 F6');
                sendHexCommand(xSerialPort, enableCmd);
                
                % 发送启动命令
                startCmd = hexString2Bytes('01 06 31 00 00 03 C7 37');
                sendHexCommand(xSerialPort, startCmd);
                
                % 等待位移完成（估计时间：0.5秒/mm）
                waitTime = abs(nextStepX) * waitPerMM;
                pause(waitTime);
                
                % 更新当前位置
                currentXPosition = nextX;
                validXPosition = nextX;
                xPosEdit.Value = nextX;
            end
            
            % 执行Y轴位移
            if abs(nextStepY) > 0.1
                % 计算圈数（1圈 = 10mm）
                circles = nextStepY / 10;
                
                % 生成电机命令
                cmd = generate_motor_command(circles);
                
                % 发送命令到Y轴
                sendHexCommand(ySerialPort, cmd);
                fprintf('Y轴位移命令已发送，位移量: %.2f mm\n', nextStepY);
                
                % 发送使能命令
                enableCmd = hexString2Bytes('01 06 31 00 00 01 46 F6');
                sendHexCommand(ySerialPort, enableCmd);
                
                % 发送启动命令
                startCmd = hexString2Bytes('01 06 31 00 00 03 C7 37');
                sendHexCommand(ySerialPort, startCmd);
                
                % 等待位移完成（估计时间：0.5秒/mm）
                waitTime = abs(nextStepY) * waitPerMM;
                pause(waitTime);
                
                % 更新当前位置
                currentYPosition = nextY;
                validYPosition = nextY;
                yPosEdit.Value = nextY;
            end
            
            % 执行Z轴位移
            if abs(nextStepZ) > 0.1
                % 计算圈数（1圈 = 10mm）
                circles = nextStepZ / 10;
                
                % 生成电机命令
                cmd = generate_motor_command(circles);
                
                % 发送命令到Z轴
                sendHexCommand(zSerialPort, cmd);
                fprintf('Z轴位移命令已发送，位移量: %.2f mm\n', nextStepZ);
                
                % 发送使能命令
                enableCmd = hexString2Bytes('01 06 31 00 00 01 46 F6');
                sendHexCommand(zSerialPort, enableCmd);
                
                % 发送启动命令
                startCmd = hexString2Bytes('01 06 31 00 00 03 C7 37');
                sendHexCommand(zSerialPort, startCmd);
                
                % 等待位移完成（估计时间：0.5秒/mm）
                waitTime = abs(nextStepZ) * waitPerMM;
                pause(waitTime);
                
                % 更新当前位置
                currentZPosition = nextZ;
                validZPosition = nextZ;
                zPosEdit.Value = nextZ;
            end
            
            % 检查是否完成所有位移
            if abs(stepXRemaining) <= 0.1 && abs(stepYRemaining) <= 0.1 && abs(stepZRemaining) <= 0.1
                currentStatus = statusBox.Value;
                if ischar(currentStatus)
                    statusBox.Value = sprintf('%s\n所有位移已完成！', currentStatus);
                elseif iscell(currentStatus)
                    statusBox.Value = [currentStatus; {'所有位移已完成！'}];
                else
                    statusBox.Value = [currentStatus; '所有位移已完成！'];
                end
                isStepMoving = false;
                isAutoRunning = false;
                
                % 如果有定时器在运行，停止并删除
                if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
                    stop(checkStatusTimer);
                    delete(checkStatusTimer);
                    checkStatusTimer = [];
                end
            else
                % 如果是自动运行模式，直接采集并保存（不发送STOP/RUN/SINGLE）
                if isConnected && ~isempty(scopeObj) && isAutoRunning
                    try
                        acquireScreenDataAndSave();
                    catch ME
                        addStatusMessage(['自动模式采集失败: ', ME.message]);
                    end
                end
            end
            
        catch ME
            currentStatus = statusBox.Value;
            if ischar(currentStatus)
                statusBox.Value = sprintf('%s\n移动到下一个位置失败: %s', currentStatus, ME.message);
            elseif iscell(currentStatus)
                statusBox.Value = [currentStatus; {sprintf('移动到下一个位置失败: %s', ME.message)}];
            else
                statusBox.Value = [currentStatus; sprintf('移动到下一个位置失败: %s', ME.message)];
            end
            fprintf('移动到下一个位置失败: %s\n', ME.message);
            isStepMoving = false;
            isAutoRunning = false;
            
            % 如果有定时器在运行，停止并删除
            if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
                stop(checkStatusTimer);
                delete(checkStatusTimer);
                checkStatusTimer = [];
            end
        end
    end
    
    % 检查示波器状态的回调函数
    function checkScopeStatus(~, ~)
        try
            if ~isConnected || isempty(scopeObj)
                % 如果示波器未连接，停止定时器
                if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
                    stop(checkStatusTimer);
                    delete(checkStatusTimer);
                    checkStatusTimer = [];
                end
                return;
            end
            
            % 查询触发状态
            fprintf(scopeObj, ':TRIGger:STATus?');
            trigStatus = fscanf(scopeObj);
            
            % 如果触发已停止，采集数据并移动到下一个位置
            if contains(trigStatus, 'STOP')
                % 停止定时器
                if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
                    stop(checkStatusTimer);
                    delete(checkStatusTimer);
                    checkStatusTimer = [];
                end
                
                % 更新状态
                currentStatus = statusBox.Value;
                if ischar(currentStatus)
                    statusBox.Value = sprintf('%s\n示波器触发完成，开始采集数据...', currentStatus);
                elseif iscell(currentStatus)
                    statusBox.Value = [currentStatus; {'示波器触发完成，开始采集数据...'}];
                else
                    statusBox.Value = [currentStatus; '示波器触发完成，开始采集数据...'];
                end
                
                % 采集数据
                acquireCallback();
            end
        catch ME
            fprintf('检查示波器状态失败: %s\n', ME.message);
            % 如果出错，停止定时器
            if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
                stop(checkStatusTimer);
                delete(checkStatusTimer);
                checkStatusTimer = [];
            end
        end
    end
    
    % 窗口关闭时的清理函数
    fig.CloseRequestFcn = @closeCallback;
    
    function closeCallback(~, ~)
        % 如果有定时器在运行，停止并删除
        if ~isempty(checkStatusTimer) && isvalid(checkStatusTimer)
            stop(checkStatusTimer);
            delete(checkStatusTimer);
            checkStatusTimer = [];
        end
        
        % 确保在关闭窗口前断开连接
        if isConnected && ~isempty(scopeObj)
            try
                fclose(scopeObj);
                delete(scopeObj);
            catch
            end
        end
        
        % 关闭三维位移控制的串口连接
        if serialConnected
            try
                % 获取串口对象
                if exist('serialObjX', 'var') && ~isempty(serialObjX)
                    sX = serialObjX;
                    % 关闭串口连接
                    if verLessThan('matlab', '9.7') % R2019b之前的版本
                        if strcmp(get(sX, 'Status'), 'open')
                            fclose(sX);
                        end
                        delete(sX);
                    else % R2019b及以后的版本
                        clear sX;
                    end
                end
                
                if exist('serialObjY', 'var') && ~isempty(serialObjY)
                    sY = serialObjY;
                    % 关闭串口连接
                    if verLessThan('matlab', '9.7') % R2019b之前的版本
                        if strcmp(get(sY, 'Status'), 'open')
                            fclose(sY);
                        end
                        delete(sY);
                    else % R2019b及以后的版本
                        clear sY;
                    end
                end
                
                if exist('serialObjZ', 'var') && ~isempty(serialObjZ)
                    sZ = serialObjZ;
                    % 关闭串口连接
                    if verLessThan('matlab', '9.7') % R2019b之前的版本
                        if strcmp(get(sZ, 'Status'), 'open')
                            fclose(sZ);
                        end
                        delete(sZ);
                    else % R2019b及以后的版本
                        clear sZ;
                    end
                end
            catch ME
                fprintf('关闭串口时出错: %s\n', ME.message);
            end
        end

        % 额外强制关闭并删除所有遗留的仪器对象（VISA/IC），防止下次打开失败（如DG2000未fclose）
        try
            objs = instrfind; % 查找所有仪器对象（visa/tcpip/serial旧接口等）
            for k = 1:numel(objs)
                try
                    % 若对象仍处于打开状态，则先关闭
                    if isprop(objs(k), 'Status') && strcmpi(objs(k).Status, 'open')
                        fclose(objs(k));
                    end
                catch
                end
                try
                    delete(objs(k));
                catch
                end
            end
            % 保险措施：重置所有仪器会话（会关闭并删除所有对象）
            instrreset;
        catch ME
            fprintf('重置仪器对象失败: %s\n', ME.message);
        end
        
        delete(fig);
    end
    
    % 串口连接/断开回调函数
    function serialConnectCallback(~, ~)
        if serialConnBtn.Value  % 连接
            try
                addStatusMessage('正在连接串口...');
                
                % 创建X轴串口对象
                if verLessThan('matlab', '9.7') % R2019b之前的版本
                    serialObjX = serial(comPortX, 'BaudRate', baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits, 'Timeout', 10);
                else % R2019b及以后的版本
                    serialObjX = serialport(comPortX, baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits);
                    % 新版串口额外配置
                    configureTerminator(serialObjX, 'CR/LF');
                    flush(serialObjX);
                end
                % 统一设置超时时间
                try
                    serialObjX.Timeout = 10;
                catch
                end
                
                % 创建Y轴串口对象
                if verLessThan('matlab', '9.7')
                    serialObjY = serial(comPortY, 'BaudRate', baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits, 'Timeout', 10);
                else
                    serialObjY = serialport(comPortY, baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits);
                    % 新版串口额外配置
                    configureTerminator(serialObjY, 'CR/LF');
                    flush(serialObjY);
                end
                % 统一设置超时时间
                try
                    serialObjY.Timeout = 10;
                catch
                end
                
                % 创建Z轴串口对象
                if verLessThan('matlab', '9.7')
                    serialObjZ = serial(comPortZ, 'BaudRate', baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits, 'Timeout', 10);
                else
                    serialObjZ = serialport(comPortZ, baudRate, 'DataBits', dataBits, ...
                        'Parity', parity, 'StopBits', stopBits);
                    % 新版串口额外配置
                    configureTerminator(serialObjZ, 'CR/LF');
                    flush(serialObjZ);
                end
                % 统一设置超时时间
                try
                    serialObjZ.Timeout = 10;
                catch
                end
                
                % 打开串口连接（旧版MATLAB）
                if verLessThan('matlab', '9.7')
                    fopen(serialObjX);
                    fopen(serialObjY);
                    fopen(serialObjZ);
                end
                
                serialConnected = true;
                serialConnBtn.Text = '断开串口';
                addStatusMessage('所有串口连接成功！');
                addStatusMessage(['X轴: ', comPortX, ', Y轴: ', comPortY, ', Z轴: ', comPortZ]);
                % 连接成功后启用初始化按钮
                initBtn.Enable = 'on';
                setStopButtonEnabled(false);
                setAuxButtonsEnabled(false);
                
            catch ME
                addStatusMessage(['串口连接失败: ', ME.message]);
                serialConnected = false;
                serialConnBtn.Value = false;
                serialConnBtn.Text = '连接串口';
            end
        else  % 断开
            try
                addStatusMessage('正在断开串口连接...');
                
                % 关闭串口连接
                if ~isempty(serialObjX)
                    if verLessThan('matlab', '9.7')
                        if strcmp(get(serialObjX, 'Status'), 'open')
                            fclose(serialObjX);
                        end
                        delete(serialObjX);
                    else
                        clear serialObjX;
                    end
                    serialObjX = [];
                end
                
                if ~isempty(serialObjY)
                    if verLessThan('matlab', '9.7')
                        if strcmp(get(serialObjY, 'Status'), 'open')
                            fclose(serialObjY);
                        end
                        delete(serialObjY);
                    else
                        clear serialObjY;
                    end
                    serialObjY = [];
                end
                
                if ~isempty(serialObjZ)
                    if verLessThan('matlab', '9.7')
                        if strcmp(get(serialObjZ, 'Status'), 'open')
                            fclose(serialObjZ);
                        end
                        delete(serialObjZ);
                    else
                        clear serialObjZ;
                    end
                    serialObjZ = [];
                end
                
                serialConnected = false;
                systemInitialized = false;
                serialConnBtn.Text = '连接串口';
                addStatusMessage('所有串口断开成功！');
                % 断开后禁用初始化与位移按钮
                initBtn.Enable = 'off';
                moveBtn.Enable = 'off';
                setStopButtonEnabled(false);
                setAuxButtonsEnabled(false);
                
            catch ME
                addStatusMessage(['断开串口失败: ', ME.message]);
            end
        end
    end
    
    % 添加状态信息
    function addStatusMessage(message)
        if ishandle(statusBox)
            currentMessages = statusBox.Value;
            if ischar(currentMessages)
                currentMessages = {currentMessages};
            end
            newMessages = [currentMessages; {[datestr(now, 'HH:MM:SS'), ' - ', message]}];
            if length(newMessages) > 20  % 限制显示条数
                newMessages = newMessages(end-19:end);
            end
            statusBox.Value = newMessages;
        end
    end
    
    % 系统初始化回调函数
    function initializeSystem(~, ~)
        if ~serialConnected
            addStatusMessage('错误：请先连接串口！');
            return;
        end
        
        if ~systemInitialized
            % 执行初始化
            addStatusMessage('正在初始化系统...');
            
            % 定义初始化命令列表
            % VDI1为伺服使能
            % % VDI2为多段位置使能
            % % 控制模式为位置模式
            % 设置多段位置指令给定
            % DI切换运行
            % 转速为30r/min，线速度5mm/s
            hexCommands = {
            % ========= 原有多段位置初始化 =========
            '01 06 17 00 00 01 4D BE',   % P17-00 = 1  VDI1 为伺服使能
            '01 06 17 02 00 1C 2C 77',   % P17-02 = 28 VDI2 为多段位置使能
            '01 06 02 00 00 01 49 B2',   % P02-00 = 1  位置模式
            '01 06 05 00 00 02 08 C7',   % P05-00 = 2  多段位置指令给定
            '01 06 11 00 00 02 0D 37',   % P11-00 = 2  DI 切换运行
            '01 06 11 0E 00 1E 6D 3D',   % P11-14 = 30 转速 30 r/min

            % ========= 回零功能初始化（新增） =========
            '01 06 03 10 00 00 88 4B',   % P03-16 = 0  DI8 无功能
            '01 06 05 1E 00 01 28 C0',   % P05-30 = 1  启用 DI 控制原点
            '01 06 05 1F 00 01 79 00',   % P05-31 = 1  回零方式（示例：方式1）
            '01 06 17 04 00 20 CC 67',   % P17-04 = 32 VDI3 为原点启动
            '01 06 0C 09 00 01 48 F3'    % P0C-09 = 1  允许 VDI 控制    
            };
            
            try
                % 初始化所有三个轴
                axes = {'X', 'Y', 'Z'};
                serialObjs = {serialObjX, serialObjY, serialObjZ};
                
                for axisIdx = 1:3
                    axisName = axes{axisIdx};
                    s = serialObjs{axisIdx};
                    
                    addStatusMessage(['初始化', axisName, '轴...']);
                    
                    % 发送所有初始化命令
                    for cmdIdx = 1:length(hexCommands)
                        byteArray = hexString2Bytes(hexCommands{cmdIdx});
                        sendHexCommand(s, byteArray);
                        pause(0.1);
                        
                        % 检查响应
                        if verLessThan('matlab', '9.7')
                            if get(s, 'BytesAvailable') > 0
                                response = fread(s, get(s, 'BytesAvailable'), 'uint8');
                            end
                        else
                            if s.NumBytesAvailable > 0
                                response = read(s, s.NumBytesAvailable, 'uint8');
                            end
                        end
                    end
                end
                
                % 重置位置变量 - 将当前位置设为0点（初始参考点）
                currentXPosition = 0;
                currentYPosition = 0;
                currentZPosition = 0;
                xPosition = 0;
                yPosition = 0;
                zPosition = 0;
                validXPosition = 0;
                validYPosition = 0;
                validZPosition = 0;
                
                addStatusMessage('重置位置变量：将当前位置设为0点（初始参考点）');
                
                % 更新UI显示（移除滑块，仅更新数值输入框）
                xPosEdit.Value = 0;
                yPosEdit.Value = 0;
                zPosEdit.Value = 0;
                
                systemInitialized = true;
                addStatusMessage('系统初始化完成！当前位置已设为0点（初始参考点）');
                addStatusMessage('提示：现在可以设置目标位置并执行位移，系统将计算相对位移量');
                % 初始化完成后启用执行位移按钮
                moveBtn.Enable = 'on';
                setAuxButtonsEnabled(true);
                
            catch ME
                addStatusMessage(['初始化失败: ', ME.message]);
                systemInitialized = false;
                % 初始化失败，保持位移按钮禁用
                moveBtn.Enable = 'off';
                setAuxButtonsEnabled(false);
            end
            
        else
            % 执行断开使能
            addStatusMessage('正在断开系统使能...');
            
            disableCommand = '01 06 31 00 00 00 87 36';
            
            try
                axes = {'X', 'Y', 'Z'};
                serialObjs = {serialObjX, serialObjY, serialObjZ};
                
                for axisIdx = 1:3
                    axisName = axes{axisIdx};
                    s = serialObjs{axisIdx};
                    
                    addStatusMessage(['断开', axisName, '轴使能...']);
                    
                    byteArray = hexString2Bytes(disableCommand);
                    sendHexCommand(s, byteArray);
                    pause(0.1);
                    
                    % 检查响应
                    if verLessThan('matlab', '9.7')
                        if get(s, 'BytesAvailable') > 0
                            response = fread(s, get(s, 'BytesAvailable'), 'uint8');
                        end
                    else
                        if s.NumBytesAvailable > 0
                            response = read(s, s.NumBytesAvailable, 'uint8');
                        end
                    end
                end
                
                systemInitialized = false;
                addStatusMessage('断开使能完成！');
                setStopButtonEnabled(false);
                setAuxButtonsEnabled(false);
                
            catch ME
                addStatusMessage(['断开使能失败: ', ME.message]);
            end
        end
    end
    
    % 执行位移回调函数
    function executeMovement(~, ~)
        if ~serialConnected
            addStatusMessage('错误：请先连接串口！');
            return;
        end
        
        if ~systemInitialized
            addStatusMessage('错误：系统未初始化，请先点击初始化按钮！');
            return;
        end
        
        if isMovementExecuting
            addStatusMessage('位移正在执行中，请先停止或等待完成');
            return;
        end

        stopRequested = false;
        isMovementExecuting = true;
        setStopButtonEnabled(true);
        cleanupObj = onCleanup(@() endMovementExecution()); %#ok<NASGU>

        try
            if trajectoryEnabled
                executeTrajectoryScan();
                return;
            end

            % 保持以程序记录的当前位置为准，避免把目标值当作当前位置
            % 获取目标位置（从目标变量读取，避免把UI输入当成当前位置）
            targetXPos = targetXPosition;
            targetYPos = targetYPosition;
            targetZPos = targetZPosition;
            
            % 计算位移量（目标位置 - 当前位置）
            xDiff = targetXPos - currentXPosition;
            yDiff = targetYPos - currentYPosition;
            zDiff = targetZPos - currentZPosition;
            
            addStatusMessage('开始执行位移...');
            addStatusMessage(['当前位置: X=', num2str(currentXPosition), ', Y=', num2str(currentYPosition), ', Z=', num2str(currentZPosition)]);
            addStatusMessage(['目标位置: X=', num2str(targetXPos), ', Y=', num2str(targetYPos), ', Z=', num2str(targetZPos)]);
            addStatusMessage(['计算位移量: X=', num2str(xDiff), ', Y=', num2str(yDiff), ', Z=', num2str(zDiff)]);
            
            % 检查是否需要移动
            if abs(xDiff) < 0.01 && abs(yDiff) < 0.01 && abs(zDiff) < 0.01
                addStatusMessage('目标位置与当前位置相同，无需位移');
                return;
            end
            
            if movementMode == 1
                % 持续位移模式
                addStatusMessage('执行持续位移模式');
                executeContinuousMovement(xDiff, yDiff, zDiff);
            else
                % 间隔位移模式
                addStatusMessage('执行间隔位移模式');
                executeIntervalMovement(xDiff, yDiff, zDiff);
            end
            
            % 注意：当前位置将在实际位移完成后由executeAxisMovement函数更新
            addStatusMessage('位移命令已发送，等待执行完成...');
            addStatusMessage(['目标位置: X=', num2str(targetXPos), ', Y=', num2str(targetYPos), ', Z=', num2str(targetZPos)]);
            
        catch ME
            addStatusMessage(['位移执行失败: ', ME.message]);
        end
    end

    function endMovementExecution()
        isMovementExecuting = false;
        stopRequested = false;
        setStopButtonEnabled(false);
        drawnow;
    end

    % 同步当前位置与UI（防止之前位移未更新变量导致从0开始）
    function syncCurrentPositionsFromUI()
        try
            if exist('xPosEdit','var') && ishandle(xPosEdit)
                currentXPosition = xPosEdit.Value;
                validXPosition = currentXPosition;
            end
            if exist('yPosEdit','var') && ishandle(yPosEdit)
                currentYPosition = yPosEdit.Value;
                validYPosition = currentYPosition;
            end
            if exist('zPosEdit','var') && ishandle(zPosEdit)
                currentZPosition = zPosEdit.Value;
                validZPosition = currentZPosition;
            end
        catch
            % 若UI控件不存在或未初始化，则保持当前变量值不变
        end
    end
    
    % 执行持续位移（并行各轴）
    function executeContinuousMovement(xDiff, yDiff, zDiff)
        % 并行发送各轴位移命令（不相互等待）
        if abs(xDiff) > 0
            executeAxisMovementAsync(serialObjX, 'X', xDiff);
        end
        if abs(yDiff) > 0
            executeAxisMovementAsync(serialObjY, 'Y', yDiff);
        end
        if abs(zDiff) > 0
            executeAxisMovementAsync(serialObjZ, 'Z', zDiff);
        end

        % 计算本次持续位移的最大等待时间（每毫米0.5秒）
        maxWait = max([0, abs(xDiff), abs(yDiff), abs(zDiff)]) * waitPerMM;
        if maxWait > 0
            addStatusMessage(['持续位移并行执行，预计最长等待 ', num2str(maxWait), ' 秒...']);
            if waitInterruptible(maxWait)
                addStatusMessage('持续位移已停止');
                return;
            end
        end

        % 统一更新所有轴的当前位置与UI
        updateAllAxisPositions(xDiff, yDiff, zDiff);
    end
    
    % 执行间隔位移
    function executeIntervalMovement(xDiff, yDiff, zDiff)
        % 在开始位移前，重置B模式图像并采集一次屏幕数据（不发送RUN/STOP）
        try
            % 重置B模式图像缓存
            bmodeImg = [];
            bmodeDepth = [];
            bmodeLateral = [];
            bmodeColCount = 0;
            globalEnvMax = 0;
            cla(bmodeAxes);
            bmodePanel.Title = 'B模式成像';
        catch ME
            addStatusMessage(['重置B模式失败: ', ME.message]);
        end
        % 首列采集
        try
            acquireScreenDataAndSave();
        catch ME
            addStatusMessage(['初始采集/保存失败: ', ME.message, '，继续执行位移']);
        end

        % 计算每轴需要的步数
        xSteps = calculateSteps(xDiff, intervalDistance);
        ySteps = calculateSteps(yDiff, intervalDistance);
        zSteps = calculateSteps(zDiff, intervalDistance);
        
        % 获取最大步数
        maxSteps = max([length(xSteps), length(ySteps), length(zSteps)]);
        
        addStatusMessage(['间隔位移将分', num2str(maxSteps), '步完成，每步采前等待 ', num2str(preAcquireDelay), ' 秒']);
        
        % 逐步执行位移
        for step = 1:maxSteps
            if stopRequested
                addStatusMessage('间隔位移已停止');
                return;
            end
            addStatusMessage(['执行第', num2str(step), '/', num2str(maxSteps), '步位移']);
            
            % 并行发送各轴位移命令（不等待完成）
            % X轴位移
            if step <= length(xSteps)
                executeAxisMovementAsync(serialObjX, 'X', xSteps(step));
            end
            
            % Y轴位移
            if step <= length(ySteps)
                executeAxisMovementAsync(serialObjY, 'Y', ySteps(step));
            end
            
            % Z轴位移
            if step <= length(zSteps)
                executeAxisMovementAsync(serialObjZ, 'Z', zSteps(step));
            end
            
            addStatusMessage(['采前等待 ', num2str(preAcquireDelay), ' 秒...']);
            if waitInterruptible(preAcquireDelay)
                addStatusMessage('间隔位移已停止');
                return;
            end

            % 每步位移完成后：先更新当前位置与UI，再采集屏幕数据并保存（不发送RUN/STOP）
            try
                % 以本步位移量刷新当前位置与UI（避免越界访问步数组）
                if step <= length(xSteps)
                    stepDx = xSteps(step);
                else
                    stepDx = 0;
                end
                if step <= length(ySteps)
                    stepDy = ySteps(step);
                else
                    stepDy = 0;
                end
                if step <= length(zSteps)
                    stepDz = zSteps(step);
                else
                    stepDz = 0;
                end

                updateAllAxisPositions(stepDx, stepDy, stepDz);

                % 刷新后进行采集与保存（直接存储，不切换运行状态）
                acquireScreenDataAndSave();
            catch ME
                addStatusMessage(['步后更新/采集/保存失败: ', ME.message, '，继续下一步']);
            end
            
        end
        
        % 所有步已在循环中逐步更新当前位置与UI，这里不再重复总更新
    end

    function stopMovement(~, ~)
        if ~serialConnected || ~systemInitialized
            addStatusMessage('停止位移失败：串口未连接或系统未初始化');
            return;
        end
        stopRequested = true;
        cmd = '01 06 0D 05 00 01 5B 66';
        try
            serialObjs = {serialObjX, serialObjY, serialObjZ};
            for idx = 1:numel(serialObjs)
                s = serialObjs{idx};
                if ~isempty(s)
                    sendHexCommand(s, cmd);
                end
            end
            addStatusMessage('已发送停止位移命令');
        catch ME
            addStatusMessage(['停止位移命令发送失败: ', ME.message]);
        end
    end

    function returnToOrigin(~, ~)
        if ~serialConnected || ~systemInitialized
            addStatusMessage('返回起点失败：串口未连接或系统未初始化');
            return;
        end
        stopRequested = true;
        enableCmd = '01 06 31 00 00 01 46 F6';
        homeCmd = '01 06 31 00 00 05 47 35';
        try
            serialObjs = {serialObjX, serialObjY, serialObjZ};
            for idx = 1:numel(serialObjs)
                s = serialObjs{idx};
                if ~isempty(s)
                    sendHexCommand(s, enableCmd);
                    pause(0.05);
                    sendHexCommand(s, homeCmd);
                    pause(0.05);
                end
            end
            pause(0.2);
            currentXPosition = 0;
            currentYPosition = 0;
            currentZPosition = 0;
            validXPosition = 0;
            validYPosition = 0;
            validZPosition = 0;
            targetXPosition = 0;
            targetYPosition = 0;
            targetZPosition = 0;
            xPosition = 0;
            yPosition = 0;
            zPosition = 0;
            if exist('xPosEdit','var') && ishandle(xPosEdit)
                xPosEdit.Value = 0;
            end
            if exist('yPosEdit','var') && ishandle(yPosEdit)
                yPosEdit.Value = 0;
            end
            if exist('zPosEdit','var') && ishandle(zPosEdit)
                zPosEdit.Value = 0;
            end
            addStatusMessage('已发送返回起点命令');
        catch ME
            addStatusMessage(['返回起点命令发送失败: ', ME.message]);
        end
    end

    function setTrajectory(~, ~)
        if ~serialConnected || ~systemInitialized
            addStatusMessage('设置轨迹失败：串口未连接或系统未初始化');
            return;
        end

        dlg = uifigure('Name', '设置轨迹', 'Position', [200, 200, 420, 300], 'Resize', 'off');
        try
            dlg.WindowStyle = 'modal';
        catch
        end

        uilabel(dlg, 'Text', 'S型扫描（先不管Z轴）', 'Position', [20, 260, 380, 22], 'FontSize', 12);

        uilabel(dlg, 'Text', 'X行程 (mm):', 'Position', [20, 220, 120, 22]);
        xSpanEdit = uieditfield(dlg, 'numeric', 'Position', [150, 220, 100, 22], 'Limits', [0.1, 1000], 'Value', trajectoryParams.xSpan, 'ValueDisplayFormat', '%.2f');

        uilabel(dlg, 'Text', 'X步距 (mm):', 'Position', [20, 190, 120, 22]);
        xStepEdit = uieditfield(dlg, 'numeric', 'Position', [150, 190, 100, 22], 'Limits', [0.01, 1000], 'Value', trajectoryParams.xStep, 'ValueDisplayFormat', '%.2f');

        uilabel(dlg, 'Text', 'Y步距 (mm):', 'Position', [20, 160, 120, 22]);
        yStepEdit = uieditfield(dlg, 'numeric', 'Position', [150, 160, 100, 22], 'Limits', [0.01, 1000], 'Value', trajectoryParams.yStep, 'ValueDisplayFormat', '%.2f');

        uilabel(dlg, 'Text', 'Y行数:', 'Position', [20, 130, 120, 22]);
        yLinesEdit = uieditfield(dlg, 'numeric', 'Position', [150, 130, 100, 22], 'Limits', [1, 100000], 'RoundFractionalValues', true, 'Value', trajectoryParams.yLines, 'ValueDisplayFormat', '%.0f');

        startAtCurrentCk = uicheckbox(dlg, 'Text', '从当前位置开始', 'Position', [280, 220, 120, 22], 'Value', trajectoryParams.startAtCurrent);
        resetBmodeCk = uicheckbox(dlg, 'Text', '开始前重置B模式', 'Position', [280, 190, 120, 22], 'Value', trajectoryParams.resetBmode);
        acquireEachPointCk = uicheckbox(dlg, 'Text', '每点采集并保存', 'Position', [280, 160, 120, 22], 'Value', trajectoryParams.acquireEachPoint);

        statusText = uitextarea(dlg, 'Position', [20, 60, 380, 60], 'Editable', 'off', 'Value', '');

        function refreshSummary()
            xp = xSpanEdit.Value;
            xs = xStepEdit.Value;
            ys = yStepEdit.Value;
            yl = yLinesEdit.Value;
            pointsPerLine = floor(xp / xs) + 1;
            totalPoints = pointsPerLine * yl;
            statusText.Value = {
                sprintf('预计每行点数: %d', pointsPerLine)
                sprintf('预计总点数: %d', totalPoints)
                sprintf('总Y行程: %.2f mm', ys * (yl - 1))
            };
        end

        xSpanEdit.ValueChangedFcn = @(~,~) refreshSummary();
        xStepEdit.ValueChangedFcn = @(~,~) refreshSummary();
        yStepEdit.ValueChangedFcn = @(~,~) refreshSummary();
        yLinesEdit.ValueChangedFcn = @(~,~) refreshSummary();
        refreshSummary();

        function applySettings()
            xp = xSpanEdit.Value;
            xs = xStepEdit.Value;
            ys = yStepEdit.Value;
            yl = yLinesEdit.Value;
            if xs > xp
                xs = xp;
                xStepEdit.Value = xs;
            end
            trajectoryParams.xSpan = xp;
            trajectoryParams.xStep = xs;
            trajectoryParams.yStep = ys;
            trajectoryParams.yLines = yl;
            trajectoryParams.startAtCurrent = startAtCurrentCk.Value;
            trajectoryParams.resetBmode = resetBmodeCk.Value;
            trajectoryParams.acquireEachPoint = acquireEachPointCk.Value;
            trajectoryEnabled = true;
            addStatusMessage(sprintf('轨迹已设置：X=%.2fmm(步距%.2f), Y步距=%.2fmm, 行数=%d', xp, xs, ys, yl));
            delete(dlg);
        end

        function clearSettings()
            trajectoryEnabled = false;
            addStatusMessage('轨迹已清除');
            delete(dlg);
        end

        uibutton(dlg, 'Text', '应用', 'Position', [20, 20, 90, 28], 'ButtonPushedFcn', @(~,~) applySettings());
        uibutton(dlg, 'Text', '清除', 'Position', [120, 20, 90, 28], 'ButtonPushedFcn', @(~,~) clearSettings());
        uibutton(dlg, 'Text', '取消', 'Position', [310, 20, 90, 28], 'ButtonPushedFcn', @(~,~) delete(dlg));
    end

    function executeTrajectoryScan()
        if ~trajectoryEnabled
            addStatusMessage('未设置轨迹，按目标位置执行位移');
            return;
        end

        prevBmodeEnabled = bmodeEnabled;
        bmodeEnabled = false;
        cleanupBmode = onCleanup(@() restoreBmodeEnabled(prevBmodeEnabled)); %#ok<NASGU>

        if trajectoryParams.resetBmode && bmodeEnabled
            try
                bmodeImg = [];
                bmodeDepth = [];
                bmodeLateral = [];
                bmodeColCount = 0;
                globalEnvMax = 0;
                cla(bmodeAxes);
                bmodePanel.Title = 'B模式成像';
            catch
            end
        end

        if trajectoryParams.startAtCurrent
            startX = currentXPosition;
            startY = currentYPosition;
        else
            startX = 0;
            startY = 0;
        end

        xSpan = trajectoryParams.xSpan;
        xStep = trajectoryParams.xStep;
        yStep = trajectoryParams.yStep;
        yLines = trajectoryParams.yLines;
        acquireEachPoint = trajectoryParams.acquireEachPoint;

        if xStep <= 0
            xStep = xSpan;
        end
        pointsPerLine = max(1, floor(xSpan / xStep) + 1);

        function ok = moveRelative(dx, dy)
            ok = false;
            if stopRequested
                return;
            end

            if abs(dx) > 0
                executeAxisMovementAsync(serialObjX, 'X', dx);
            end
            if abs(dy) > 0
                executeAxisMovementAsync(serialObjY, 'Y', dy);
            end

            waitSec = max([abs(dx), abs(dy)]) * waitPerMM;
            if waitInterruptible(waitSec)
                return;
            end

            updateAllAxisPositions(dx, dy, 0);
            ok = true;
        end

        function ok = acquireIfNeeded()
            ok = true;
            if stopRequested
                ok = false;
                return;
            end
            if acquireEachPoint
                try
                    acquireScreenDataAndSave();
                catch ME
                    addStatusMessage(['采集/保存失败: ', ME.message]);
                end
            end
        end

        try
            if ~trajectoryParams.startAtCurrent
                dx0 = startX - currentXPosition;
                dy0 = startY - currentYPosition;
                if abs(dx0) > 0 || abs(dy0) > 0
                    addStatusMessage('移动到轨迹起点...');
                    if ~moveRelative(dx0, dy0)
                        addStatusMessage('轨迹已停止');
                        return;
                    end
                end
            end

            addStatusMessage(sprintf('开始S型扫描：行数=%d, 每行点数=%d', yLines, pointsPerLine));

            if ~acquireIfNeeded()
                addStatusMessage('轨迹已停止');
                return;
            end

            for lineIdx = 1:yLines
                if stopRequested
                    addStatusMessage('轨迹已停止');
                    return;
                end

                if mod(lineIdx, 2) == 1
                    dirSign = 1;
                else
                    dirSign = -1;
                end

                for p = 2:pointsPerLine
                    if stopRequested
                        addStatusMessage('轨迹已停止');
                        return;
                    end
                    dx = dirSign * xStep;
                    if p == pointsPerLine
                        remaining = xSpan - xStep * (pointsPerLine - 2);
                        if remaining < 0
                            remaining = 0;
                        end
                        dx = dirSign * remaining;
                    end
                    if abs(dx) > 0
                        if ~moveRelative(dx, 0)
                            addStatusMessage('轨迹已停止');
                            return;
                        end
                    end
                    if ~acquireIfNeeded()
                        addStatusMessage('轨迹已停止');
                        return;
                    end
                end

                if lineIdx < yLines
                    if ~moveRelative(0, yStep)
                        addStatusMessage('轨迹已停止');
                        return;
                    end
                    if ~acquireIfNeeded()
                        addStatusMessage('轨迹已停止');
                        return;
                    end
                end
            end

            addStatusMessage('S型扫描完成');
        catch ME
            addStatusMessage(['轨迹执行失败: ', ME.message]);
        end
    end

    function restoreBmodeEnabled(prevValue)
        bmodeEnabled = prevValue;
    end

    % 采集屏幕数据并保存（NORM模式，读取当前屏幕显示数据）
    function acquireScreenDataAndSave()
        if ~isConnected || isempty(scopeObj)
            error('示波器未连接');
        end
        
        % 设置为屏幕数据模式（直接读取，不发送STOP/RUN）
        fprintf(scopeObj, ':WAVeform:SOURce CHANnel1');
        fprintf(scopeObj, ':WAVeform:MODE NORM');
        fprintf(scopeObj, ':WAVeform:FORMat BYTE');

        % 获取波形参数
        fprintf(scopeObj, ':WAVeform:PREamble?');
        preamble = str2num(fscanf(scopeObj)); %#ok<ST2NM>
        if isempty(preamble) || numel(preamble) < 10
            error('无法解析示波器PREamble');
        end

        format = preamble(1);
        type = preamble(2);
        points = preamble(3);
        count = preamble(4);
        xincrement = preamble(5);
        xorigin = preamble(6);
        xreference = preamble(7);
        yincrement = preamble(8);
        yorigin = preamble(9);
        yreference = preamble(10);

        % 读取屏幕数据
        fprintf(scopeObj, ':WAVeform:DATA?');
        [data, ~] = fread(scopeObj, scopeObj.InputBufferSize);

        % 解析TMC头格式
        if ~isempty(data) && data(1) == '#'
            n_digits = str2double(char(data(2)));
            data_length = str2double(char(data(3:2+n_digits)'));
            data = data(2+n_digits+1:2+n_digits+data_length);
        else
            headerLength = find(data == 10, 1);
            if ~isempty(headerLength)
                data = data(headerLength+1:end);
            end
        end

        sampleLength = min(length(data), points);
        data = data(1:sampleLength);

        % 转换为电压与时间
        waveData = (data - yreference) * yincrement + yorigin;
        timeData = ((0:sampleLength-1) - xreference) * xincrement + xorigin;
        Fs = 1 / xincrement;
        T = sampleLength / Fs;
        F = 1 / T;

        % 更新界面波形（仅采样点视图）
        plot(waveAxes1, 1:sampleLength, waveData);
        % 实时更新B模式（单列）
        try
            updateBModeAfterAcquisition(waveData, Fs, sampleLength, currentYPosition);
        catch ME
            addStatusMessage(['B模式更新失败: ', ME.message]);
        end

        % 保存到Excel（使用“当前位移位置”而非UI目标值）
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        filename = sprintf('波形数据_%s_X=%.2f_Y=%.2f_Z=%.2f.xlsx', timestamp, currentXPosition, currentYPosition, currentZPosition);

        savePath = savePathEdit.Value;
        if ~exist(savePath, 'dir')
            [success, msg] = mkdir(savePath);
            if ~success
                error(['创建保存目录失败: ', msg]);
            end
        end
        fullFilePath = fullfile(savePath, filename);

        data_table = table(timeData(:), waveData(:), 'VariableNames', {'时间(s)', '电压(V)'});
        % 使用当前位移位置进行保存，避免首次保存误识别为目标位置
        posXForSave = currentXPosition; posYForSave = currentYPosition; posZForSave = currentZPosition;
        metadata = {
            '采样率(MSa/s)', Fs/1000000;
            '返回点数(k点)', sampleLength/1000;
            '周期(s)', T;
            '频率(Hz)', F;
            'X位置(mm)', posXForSave;
            'Y位置(mm)', posYForSave;
            'Z位置(mm)', posZForSave;
            '', ''
        };
        metadata_table = cell2table(metadata, 'VariableNames', {'参数', '值'});
        writetable(metadata_table, fullFilePath, 'Sheet', '元数据');
        writetable(data_table, fullFilePath, 'Sheet', '波形数据');
        addStatusMessage(['屏幕数据已保存: ', fullFilePath]);
        statusLabel.Text = ['状态: 已连接 - 数据已保存到Excel文件: ' fullFilePath ];
        statusLabel.FontColor = [0, 0.7, 0];
    end
    
    % 计算间隔位移步骤
    function steps = calculateSteps(totalDiff, intervalDist)
        if abs(totalDiff) == 0
            steps = [];
            return;
        end
        
        % 确定方向
        direction = sign(totalDiff);
        absDiff = abs(totalDiff);
        
        % 计算完整步数
        fullSteps = floor(absDiff / intervalDist);
        remainder = mod(absDiff, intervalDist);
        
        % 生成步骤数组
        steps = [];
        for i = 1:fullSteps
            steps(end+1) = direction * intervalDist;
        end
        
        % 添加剩余距离
        if remainder > 0
            steps(end+1) = direction * remainder;
        end
    end
    
    % 执行单轴位移
    function executeAxisMovement(serialObj, axisName, diff)
        try
            % 将位移转换为圈数（1圈=10mm）
            circles = diff / 10;
            
            % 生成Modbus命令字节数组
            cmdBytes = generate_motor_command(circles);
            
            % 确定移动方向
            if diff > 0
                direction = '前进';
            else
                direction = '后退';
            end
            
            addStatusMessage([axisName, '轴', direction, ' ', num2str(abs(diff)), ' mm']);
            
            % 显示发送的HEX命令（用于调试）
            hexStr = sprintf('%02X ', cmdBytes);
            addStatusMessage(['发送', axisName, '轴位移命令 (HEX): ', hexStr(1:end-1)]);
            
            % 发送位移命令
            sendHexCommand(serialObj, cmdBytes);
            pause(0.05); % 短暂延时
            
            % 发送使能命令
            enableCmd = hexString2Bytes('01 06 31 00 00 01 46 F6');
            sendHexCommand(serialObj, enableCmd);
            addStatusMessage(['发送', axisName, '轴使能命令 (HEX): 01 06 31 00 00 01 46 F6']);
            pause(0.05); % 短暂延时
            
            % 发送启动命令
            startCmd = hexString2Bytes('01 06 31 00 00 03 C7 37');
            sendHexCommand(serialObj, startCmd);
            addStatusMessage(['发送', axisName, '轴启动命令 (HEX): 01 06 31 00 00 03 C7 37']);
            
            % 等待位移完成（阻塞等待，防止提前更新当前位置）
            waitTime = abs(diff) * waitPerMM;
            addStatusMessage([axisName, '轴位移开始，预计需要 ', num2str(waitTime), ' 秒...']);
            pause(waitTime);
            addStatusMessage([axisName, '轴位移完成']);
            
            % 位移完成后更新对应轴的当前位置和UI
            switch upper(axisName)
                case 'X'
                    currentXPosition = currentXPosition + diff;
                    validXPosition = currentXPosition;
                    xPosEdit.Value = currentXPosition;
                case 'Y'
                    currentYPosition = currentYPosition + diff;
                    validYPosition = currentYPosition;
                    yPosEdit.Value = currentYPosition;
                case 'Z'
                    currentZPosition = currentZPosition + diff;
                    validZPosition = currentZPosition;
                    zPosEdit.Value = currentZPosition;
            end
            
        catch ME
            addStatusMessage([axisName, '轴位移失败: ', ME.message]);
        end
    end
    
    % 执行单轴位移（异步：仅发送命令，不在此处阻塞等待）
    function executeAxisMovementAsync(serialObj, axisName, diff)
        try
            % 将位移转换为圈数（1圈=10mm）
            circles = diff / 10;
            
            % 生成Modbus命令字节数组
            cmdBytes = generate_motor_command(circles);
            
            % 确定移动方向
            if diff > 0
                direction = '前进';
            else
                direction = '后退';
            end
            
            addStatusMessage([axisName, '轴', direction, ' ', num2str(abs(diff)), ' mm (并行)']);
            
            % 显示发送的HEX命令（用于调试）
            hexStr = sprintf('%02X ', cmdBytes);
            addStatusMessage(['发送', axisName, '轴位移命令 (HEX): ', hexStr(1:end-1)]);
            
            % 发送位移命令
            sendHexCommand(serialObj, cmdBytes);
            pause(0.05); % 短暂延时
            
            % 发送使能命令
            enableCmd = hexString2Bytes('01 06 31 00 00 01 46 F6');
            sendHexCommand(serialObj, enableCmd);
            addStatusMessage(['发送', axisName, '轴使能命令 (HEX): 01 06 31 00 00 01 46 F6']);
            pause(0.05); % 短暂延时
            
            % 发送启动命令
            startCmd = hexString2Bytes('01 06 31 00 00 03 C7 37');
            sendHexCommand(serialObj, startCmd);
            addStatusMessage(['发送', axisName, '轴启动命令 (HEX): 01 06 31 00 00 03 C7 37']);
            
            % 不在此处等待，等待由调用者按最大步长时间统一等待
            
        catch ME
            addStatusMessage([axisName, '轴(并行)位移失败: ', ME.message]);
        end
    end
    
    % 根据目标差值统一更新所有轴的位置与UI（在一步完成后调用）
    function updateAllAxisPositions(xDiff, yDiff, zDiff)
        if abs(xDiff) > 0
            currentXPosition = currentXPosition + xDiff;
            validXPosition = currentXPosition;
            xPosEdit.Value = currentXPosition;
        end
        
        if abs(yDiff) > 0
            currentYPosition = currentYPosition + yDiff;
            validYPosition = currentYPosition;
            yPosEdit.Value = currentYPosition;
        end
        
        if abs(zDiff) > 0
            currentZPosition = currentZPosition + zDiff;
            validZPosition = currentZPosition;
            zPosEdit.Value = currentZPosition;
        end
    end

     
     % 等待示波器触发完成并保存数据
      function waitForOscilloscopeTriggerAndSave()
          try
              % 更新状态显示
              newMessage = '示波器状态: 等待触发完成...';
              if isempty(statusBox.Value) || (ischar(statusBox.Value) && isempty(statusBox.Value))
                  statusBox.Value = newMessage;
              else
                  % 添加新消息到状态框的最上方
                  if ischar(statusBox.Value)
                      % 将字符串转换为元胞数组，然后连接
                      statusBox.Value = [{statusBox.Value}; {newMessage}];
                  elseif iscell(statusBox.Value)
                      statusBox.Value = [statusBox.Value; {newMessage}];
                  elseif isstring(statusBox.Value)
                      statusBox.Value = [statusBox.Value; string(newMessage)];
                  else
                      statusBox.Value = newMessage;
                  end
              end
              
              % 等待触发完成（轮询示波器状态）
              triggerComplete = false;
              maxWaitTime = 10; % 最大等待时间（秒）
              startTime = tic;
              
              while ~triggerComplete && toc(startTime) < maxWaitTime
                  % 查询触发状态
                  fprintf(scopeObj, ':TRIGger:STATus?');
                  pause(0.5);
                  status = fscanf(scopeObj);
                  
                  % 检查是否触发完成（STOP状态）
                  if contains(status, 'STOP')
                      triggerComplete = true;
                  else
                      pause(0.5); % 等待500毫秒再次检查
                  end
              end
              
              if triggerComplete
                  % 更新状态显示
                  newMessage = '示波器状态: 触发完成，正在保存数据...';
                  if isempty(statusBox.Value) || (ischar(statusBox.Value) && isempty(statusBox.Value))
                      statusBox.Value = newMessage;
                  else
                      % 添加新消息到状态框的最上方
                      if ischar(statusBox.Value)
                          % 将字符串转换为元胞数组，然后连接
                          statusBox.Value = [{statusBox.Value}; {newMessage}];
                      elseif iscell(statusBox.Value)
                          statusBox.Value = [statusBox.Value; {newMessage}];
                      elseif isstring(statusBox.Value)
                          statusBox.Value = [statusBox.Value; string(newMessage)];
                      else
                          statusBox.Value = newMessage;
                      end
                  end
                  
                  % 获取波形数据
                  getWaveformData();
                  
                  % 保存数据
                  saveData();
                  
                  % 更新状态显示
                  newMessage = '示波器状态: 数据已保存';
                  if isempty(statusBox.Value) || (ischar(statusBox.Value) && isempty(statusBox.Value))
                      statusBox.Value = newMessage;
                  else
                      % 添加新消息到状态框的最上方
                      if ischar(statusBox.Value)
                          % 将字符串转换为元胞数组，然后连接
                          statusBox.Value = [{statusBox.Value}; {newMessage}];
                      elseif iscell(statusBox.Value)
                          statusBox.Value = [statusBox.Value; {newMessage}];
                      elseif isstring(statusBox.Value)
                          statusBox.Value = [statusBox.Value; string(newMessage)];
                      else
                          statusBox.Value = newMessage;
                      end
                  end
              else
                  % 触发超时
                  newMessage = '示波器状态: 触发超时，继续下一步';
                  if isempty(statusBox.Value) || (ischar(statusBox.Value) && isempty(statusBox.Value))
                      statusBox.Value = newMessage;
                  else
                      % 添加新消息到状态框的最上方
                      if ischar(statusBox.Value)
                          % 将字符串转换为元胞数组，然后连接
                          statusBox.Value = [{statusBox.Value}; {newMessage}];
                      elseif iscell(statusBox.Value)
                          statusBox.Value = [statusBox.Value; {newMessage}];
                      elseif isstring(statusBox.Value)
                          statusBox.Value = [statusBox.Value; string(newMessage)];
                      else
                          statusBox.Value = newMessage;
                      end
                  end
              end
          catch ME
              uialert(fig, ['示波器数据采集失败: ' ME.message], '错误');
              fprintf('示波器数据采集失败: %s\n', ME.message);
          end
      end
      
      % 获取波形数据
      function getWaveformData()
          try
              % 获取采集长度
              acqLength = str2double(acqLengthEdit.Value);
              
              % 获取通道1数据
              fprintf(scopeObj, ':WAV:SOUR CHAN1');
              fprintf(scopeObj, ':WAV:MODE NORM');
              fprintf(scopeObj, ':WAV:FORM BYTE');
              fprintf(scopeObj, ':WAV:DATA?');
               
               % 读取通道1波形（包含TMC头）
               [raw1, ~] = fread(scopeObj, scopeObj.InputBufferSize);
              if ~isempty(raw1) && raw1(1) == '#'
                  n1 = str2double(char(raw1(2)));
                  len1 = str2double(char(raw1(3:2+n1)'));
                  waveformData1 = raw1(2+n1+1:2+n1+len1);
              else
                  % 回退方案：尝试按换行头截断
                  hl = find(raw1 == 10, 1);
                  if ~isempty(hl)
                      waveformData1 = raw1(hl+1:end);
                  else
                      waveformData1 = raw1;
                  end
              end
              
              % 获取通道2数据
              fprintf(scopeObj, ':WAV:SOUR CHAN2');
              fprintf(scopeObj, ':WAV:DATA?');
              [raw2, ~] = fread(scopeObj, scopeObj.InputBufferSize);
              if ~isempty(raw2) && raw2(1) == '#'
                  n2 = str2double(char(raw2(2)));
                  len2 = str2double(char(raw2(3:2+n2)'));
                  waveformData2 = raw2(2+n2+1:2+n2+len2);
              else
                  hl = find(raw2 == 10, 1);
                  if ~isempty(hl)
                      waveformData2 = raw2(hl+1:end);
                  else
                      waveformData2 = raw2;
                  end
              end
              
              % 获取时间数据
              fprintf(scopeObj, ':WAV:XINCrement?');
              timeIncrement = str2double(fscanf(scopeObj));
              
              % 生成时间数据
              timeData = (0:length(waveformData1)-1) * timeIncrement;
              
              % 获取垂直刻度
              fprintf(scopeObj, ':WAV:SOUR CHAN1');
              fprintf(scopeObj, ':WAV:YOR?');
              yOrigin1 = str2double(fscanf(scopeObj));
              fprintf(scopeObj, ':WAV:YREF?');
              yRef1 = str2double(fscanf(scopeObj));
              fprintf(scopeObj, ':WAV:YINC?');
              yIncrement1 = str2double(fscanf(scopeObj));
              
              fprintf(scopeObj, ':WAV:SOUR CHAN2');
              fprintf(scopeObj, ':WAV:YOR?');
              yOrigin2 = str2double(fscanf(scopeObj));
              fprintf(scopeObj, ':WAV:YREF?');
              yRef2 = str2double(fscanf(scopeObj));
              fprintf(scopeObj, ':WAV:YINC?');
              yIncrement2 = str2double(fscanf(scopeObj));
              
              % 转换为电压值
              voltageData1 = (waveformData1 - yRef1) * yIncrement1 + yOrigin1;
              voltageData2 = (waveformData2 - yRef2) * yIncrement2 + yOrigin2;
              
              % 截取指定长度的数据
              if acqLength > 0 && acqLength < length(timeData)
                  timeData = timeData(1:acqLength);
                  voltageData1 = voltageData1(1:acqLength);
                  voltageData2 = voltageData2(1:acqLength);
              end
              
              % 更新全局变量
              waveformTime = timeData;
              waveformData = [voltageData1, voltageData2];
              
              % 更新波形显示
              updateWaveformDisplay();
              
          catch ME
              uialert(fig, ['获取波形数据失败: ' ME.message], '错误');
              fprintf('获取波形数据失败: %s\n', ME.message);
          end
      end
      
      % 更新波形显示
      function updateWaveformDisplay()
          try
              % 确保waveformData和waveformTime已初始化
              if ~exist('waveformData', 'var') || isempty(waveformData) || ~exist('waveformTime', 'var') || isempty(waveformTime)
                  fprintf('波形数据或时间数据未初始化，无法显示波形\n');
                  return;
              end
              
              % 清除现有图形
              cla(waveformAxes1);
              cla(waveformAxes2);
              
              % 绘制通道1波形
              plot(waveformAxes1, waveformTime, waveformData(:,1), 'b');
              title(waveformAxes1, '通道1波形');
              xlabel(waveformAxes1, '时间 (s)');
              ylabel(waveformAxes1, '电压 (V)');
              grid(waveformAxes1, 'on');
              
              % 绘制通道2波形
              plot(waveformAxes2, waveformTime, waveformData(:,2), 'r');
              title(waveformAxes2, '通道2波形');
              xlabel(waveformAxes2, '时间 (s)');
              ylabel(waveformAxes2, '电压 (V)');
              grid(waveformAxes2, 'on');
          catch ME
              fprintf('更新波形显示失败: %s\n', ME.message);
          end
      end
      
      % 保存数据
      function saveData()
          try
              % 获取保存路径
              savePath = savePathEdit.Value;
              
              % 检查路径是否存在，如果不存在则创建
              if ~exist(savePath, 'dir')
                  mkdir(savePath);
              end
              
              % 生成文件名（使用当前时间和位置信息）
              timestamp = datestr(now, 'yyyymmdd_HHMMSS');
              filename = sprintf('%s/Data_%s_X%.2f_Y%.2f_Z%.2f.xlsx', savePath, timestamp, currentXPosition, currentYPosition, currentZPosition);
              
              % 创建元数据表格
              metadata = {'时间戳', timestamp; ...
                  'X位置', currentXPosition; ...
                  'Y位置', currentYPosition; ...
                  'Z位置', currentZPosition; ...
                  '采样率', sampleRate; ...
                  '存储深度', memDepth};
              
              % 创建波形数据表格（统一为列向量）
              waveformTable = array2table([waveformTime(:), waveformData], 'VariableNames', {'时间', '通道1', '通道2'});
              
              % 写入Excel文件
              writetable(array2table(metadata, 'VariableNames', {'参数', '值'}), filename, 'Sheet', '元数据');
              writetable(waveformTable, filename, 'Sheet', '波形数据');
              
              % 更新状态显示
              newMessage = sprintf('数据已保存至: %s', filename);
              if isempty(statusBox.Value) || (ischar(statusBox.Value) && isempty(statusBox.Value))
                  statusBox.Value = newMessage;
              else
                  % 添加新消息到状态框的最上方
                  if ischar(statusBox.Value)
                      % 将字符串转换为元胞数组，然后连接
                      statusBox.Value = [{statusBox.Value}; {newMessage}];
                  elseif iscell(statusBox.Value)
                      statusBox.Value = [statusBox.Value; {newMessage}];
                  elseif isstring(statusBox.Value)
                      statusBox.Value = [statusBox.Value; string(newMessage)];
                  else
                      statusBox.Value = newMessage;
                  end
              end
              
          catch ME
              uialert(fig, ['保存数据失败: ' ME.message], '错误');
              fprintf('保存数据失败: %s\n', ME.message);
          end
      end
      
      % 生成电机命令
      function cmd = generate_motor_command(circles)
          % 生成电机控制命令
          % 输入: circles - 圈数（正数为正转，负数为反转）
          % 输出: cmd - uint8字节数组
          
          PULSES_PER_CIRCLE = 10000; % 每圈脉冲数
          
          % 计算总脉冲数
          total_pulses = -circles * PULSES_PER_CIRCLE;
          
          % 固定的Modbus头部
          header = [0x01, 0x10, 0x11, 0x0C, 0x00, 0x02, 0x04];
          
          % 将脉冲数转换为32位有符号整数
          if total_pulses >= 0
              % 正数：直接转换
              pulse_value = uint32(total_pulses);
          else
              % 负数：使用二进制补码算法
              % 1. 取绝对值的32位表示
              abs_value = uint32(abs(total_pulses));
              % 2. 按位取反
              inverted = bitcmp(abs_value, 'uint32');
              % 3. 加一得到补码
              pulse_value = inverted + uint32(1);
          end
          
          % 提取高16位和低16位
          high_word = bitshift(pulse_value, -16);             % 高16位
          low_word = bitand(pulse_value, uint32(0xFFFF));     % 低16位
          
          % 转换为字节，每个16位字内部大端序
          high_high_byte = bitshift(high_word, -8);           % 高字的高字节
          high_low_byte = bitand(high_word, uint32(0xFF));    % 高字的低字节
          low_high_byte = bitshift(low_word, -8);             % 低字的高字节
          low_low_byte = bitand(low_word, uint32(0xFF));      % 低字的低字节
          
          % 正确排列：低字在前（大端序），高字在后（大端序）
          pulse_bytes = [double(low_high_byte), double(low_low_byte), double(high_high_byte), double(high_low_byte)];
          
          % 组合数据部分
          data_part = [header, pulse_bytes];
          
          % 计算CRC校验
          crc = crc16modbus(data_part);
          crc_low = bitand(crc, 255);
          crc_high = bitshift(crc, -8);
          
          % 组合完整的命令字节 - 确保是行向量
          cmd = uint8([data_part, crc_low, crc_high]);
          cmd = cmd(:)'; % 强制转为行向量
      end
      
      % 发送HEX命令（带简单回包检测）
      function sendHexCommand(serialPort, data)
          try
              % 验证串口对象有效性
              if isempty(serialPort)
                  addStatusMessage('错误：串口对象为空');
                  return;
              end
              
              % 发送前清空输入缓冲区
              bufferCleared = 0;
              if verLessThan('matlab', '9.7') % R2019b之前的版本
                  if serialPort.BytesAvailable > 0
                      bufferCleared = serialPort.BytesAvailable;
                      fread(serialPort, serialPort.BytesAvailable, 'uint8');
                  end
              else % R2019b及以后的版本
                  if serialPort.NumBytesAvailable > 0
                      bufferCleared = serialPort.NumBytesAvailable;
                      read(serialPort, serialPort.NumBytesAvailable, 'uint8');
                  end
              end
              
              if bufferCleared > 0
                  addStatusMessage(sprintf('清理缓冲区：%d字节', bufferCleared));
              end
              
              % 根据数据类型决定发送内容
              if ischar(data) || isstring(data)
                  % 若传入字符串，则按HEX解析为原始字节发送（例如 '01 06 ...' -> [0x01 0x06 ...]）
                  bytesToSend = hexString2Bytes(char(data));
              else
                  % 原始字节数组
                  bytesToSend = uint8(data);
              end
              
              % 确保为uint8行向量
              if ~isa(bytesToSend, 'uint8')
                  bytesToSend = uint8(bytesToSend);
              end
              bytesToSend = bytesToSend(:)';
              
              % 数据完整性检查
              if length(bytesToSend) == 0
                  addStatusMessage('错误：发送数据为空');
                  return;
              end
              
              if any(isnan(bytesToSend)) || any(isinf(bytesToSend))
                  addStatusMessage('错误：发送数据包含无效值');
                  return;
              end

              % 调试：记录发送的HEX
              pName = '';
              try
                  if verLessThan('matlab','9.7')
                      pName = get(serialPort,'Port');
                  else
                      pName = serialPort.Port;
                  end
              catch
                  pName = '未知端口';
              end
              
              hexStr = sprintf('%02X ', bytesToSend);
              addStatusMessage(sprintf('发送[%s] %d字节: %s', pName, length(bytesToSend), hexStr(1:end-1)));

              % 发送数据前短暂延时确保缓冲区清空完成
              pause(0.005);
              
              if verLessThan('matlab', '9.7')
                  fwrite(serialPort, bytesToSend, 'uint8');
              else
                  write(serialPort, bytesToSend, 'uint8');
              end
              
              % 等待设备响应（最长150ms）
              maxWait = 0.15; % 150毫秒
              t0 = tic;
              responseReceived = false;
              
              if verLessThan('matlab', '9.7')
                  while toc(t0) < maxWait
                      if serialPort.BytesAvailable > 0
                          response = fread(serialPort, serialPort.BytesAvailable, 'uint8');
                          responseReceived = true;
                          break;
                      end
                      pause(0.002);
                  end
              else
                  while toc(t0) < maxWait
                      if serialPort.NumBytesAvailable > 0
                          response = read(serialPort, serialPort.NumBytesAvailable, 'uint8');
                          responseReceived = true;
                          break;
                      end
                      pause(0.002);
                  end
              end
              
              if responseReceived
                  hexResp = sprintf('%02X ', response);
                  addStatusMessage(sprintf('收到[%s]响应 %d字节: %s', pName, length(response), hexResp(1:end-1)));
                  
                  % 检查是否为异常响应模式
                  if length(response) >= 2 && all(response == 255) % 全部是FF
                      addStatusMessage('警告：收到异常响应模式(全FF)，可能设备未正确接收命令');
                  end
              else
                  addStatusMessage(sprintf('超时[%s]：%.0fms内无响应', pName, maxWait*1000));
              end
              
          catch ME
              addStatusMessage(sprintf('HEX命令发送失败: %s', ME.message));
          end
      end
      
      % 将HEX字符串转换为字节数组
      function byteArray = hexString2Bytes(hexStr)
          try
              % 移除所有空格和其他分隔符
              hexStr = strrep(hexStr, ' ', '');
              hexStr = strrep(hexStr, ',', '');
              hexStr = strrep(hexStr, ';', '');
              hexStr = strrep(hexStr, '0x', '');
              hexStr = strrep(hexStr, '0X', '');
              
              % 验证输入只包含有效的十六进制字符
              if ~isempty(regexp(hexStr, '[^0-9A-Fa-f]', 'once'))
                  error('输入包含非十六进制字符');
              end
              
              % 确保字符串长度为偶数
              if mod(length(hexStr), 2) ~= 0
                  hexStr = ['0', hexStr];
              end
              
              % 检查是否为空字符串
              if isempty(hexStr)
                  byteArray = uint8([]);
                  return;
              end
              
              % 转换为字节数组
              hexPairs = reshape(hexStr, 2, [])';
              byteArray = uint8(hex2dec(hexPairs));
              
              % 验证结果
              if any(isnan(byteArray)) || any(isinf(double(byteArray)))
                  error('转换结果包含无效值');
              end
          catch ME
              % 转换失败时记录错误并返回空数组
              addStatusMessage(['HEX字符串转换失败: ', ME.message]);
              byteArray = uint8([]);
          end
      end
      
      % 获取高字节
      function b = highbyte(word)
          b = bitshift(bitand(word, 65280), -8);
      end
      
      % 获取低字节
      function b = lowbyte(word)
          b = bitand(word, 255);
      end
      
      % 更新位移状态显示框
      function updateStatusBox(message)
          % 获取当前状态
          currentStatus = statusBox.Value;
          
          % 添加新消息
          if isempty(currentStatus) || (ischar(currentStatus) && isempty(currentStatus))
              statusBox.Value = message;
          else
              % 添加新消息到状态框
              if ischar(currentStatus)
                  % 将字符串转换为元胞数组，然后连接
                  statusBox.Value = [{currentStatus}; {message}];
              elseif iscell(currentStatus)
                  statusBox.Value = [currentStatus; {message}];
              elseif isstring(currentStatus)
                  statusBox.Value = [currentStatus; string(message)];
              else
                  statusBox.Value = message;
              end
          end
      end
      
      % CRC16 Modbus计算函数
      function crc = crc16modbus(data)
          % 初始化CRC值
          crc = uint16(65535);
          
          % 对每个字节进行处理
          for i = 1:length(data)
              crc = bitxor(crc, uint16(data(i)));
              
              % 处理8位
              for j = 1:8
                  % 检查最低位
                  if bitand(crc, 1) ~= 0
                      % 右移一位并异或多项式0xA001
                      crc = bitshift(crc, -1);
                      crc = bitxor(crc, uint16(hex2dec('A001')));
                  else
                      % 仅右移一位
                      crc = bitshift(crc, -1);
                  end
              end
          end
          
          % 返回CRC值
          crc = uint16(crc);
      end
    end

    
