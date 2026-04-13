function AcousticScanUI_Ultimate
% AcousticScanUI_Ultimate 3D Scatter + Surface Edition
% 【最终成神版 - PRF 改为必须手动输入且必须大于 0】
% 【更新 1：修复高频噪声尖刺导致中心频率 Fc 计算错误的问题（平滑滤波法）】
% 【更新 2：在单波形图中添加红色竖线（展示截取区间）和绿色横线（展示 10% 阈值）】
% 【更新 3：新增“⑧ 声轴对齐”选项卡，支持基于两条不同 Y 截面的扫描线计算 X/Z 方向偏转角】
% 【更新 4：修复声轴对齐页上半区高度不足，确保 X/Z 两个计算按钮完整显示】
% 【更新 5：当 PRF 输入有效时，在状态栏给出明确提示；当 PRF<=0 时直接报错】
% 【更新 6：界面初始 PRF 默认值改为 NaN；若用户未输入，则提示“请输入 PRF”】
% 【更新 7：将 PRF 输入框改为文本框以支持初始显示 NaN，并在计算时转数值校验】
% 【更新 8：修复 1D 数据时一维切面不绘图的问题；哪个轴在变化，就画哪个轴的曲线】
% 【更新 9：PRF 未输入时不向系统抛错，改为软件界面弹窗提醒】
% 运行方式：在MATLAB命令行输入 AcousticScanUI_Ultimate

    % ============================================================
    % 0. 颜色常量与主题配置
    % ============================================================
    COLORS = struct();
    COLORS.bg = [0.96 0.96 0.96];
    COLORS.panelBg = [1 1 1];
    COLORS.primary = [0 0.45 0.74];
    COLORS.secondary = [0.2 0.6 0.4];
    COLORS.accent = [0.85 0.33 0.1];
    COLORS.text = [0.2 0.2 0.2];
    COLORS.textLight = [0.5 0.5 0.5];
    COLORS.border = [0.85 0.85 0.85];

    % ============================================================
    % 1. 主窗口与选项卡组（响应式布局）
    % ============================================================
    screenSize = get(groot, 'ScreenSize');
    figWidth = min(1300, screenSize(3) - 100);
    figHeight = min(900, screenSize(4) - 100);
    figX = (screenSize(3) - figWidth) / 2;
    figY = (screenSize(4) - figHeight) / 2;

    app = struct();
    app.fig = uifigure('Name','Acoustic Analyzer Pro','Position',[figX figY figWidth figHeight]);
    app.fig.Color = COLORS.bg;
    app.fig.AutoResizeChildren = 'on';

    mainGrid = uigridlayout(app.fig, [1 1]);
    mainGrid.Padding = [8 8 8 8];

    app.tg = uitabgroup(mainGrid);
    app.tg.Layout.Row = 1;
    app.tg.Layout.Column = 1;

    app.tabInput  = uitab(app.tg, 'Title', '  ① 参数输入  ');
    app.tabSingle = uitab(app.tg, 'Title', '  ② 单波形分析  ');
    app.tabLinear = uitab(app.tg, 'Title', '  ③ 一维切面  ');
    app.tab2D     = uitab(app.tg, 'Title', '  ④ 二维热力图  ');
    app.tab3D     = uitab(app.tg, 'Title', '  ⑤ 3D 点云  ');
    app.tabSurfXZ = uitab(app.tg, 'Title', '  ⑥ XZ 曲面  ');
    app.tabReport = uitab(app.tg, 'Title', '  ⑦ 报告与数据  ');
    app.tabAlign  = uitab(app.tg, 'Title', '  ⑧ 声轴对齐  ');

    % ============================================================
    % 2. 界面 1: Input (输入设置)
    % ============================================================
    inputMainGrid = uigridlayout(app.tabInput, [3 1]);
    inputMainGrid.RowHeight = {'1x', 70, 50};
    inputMainGrid.Padding = [15 15 15 15];

    paramArea = uigridlayout(inputMainGrid, [1 2]);
    paramArea.ColumnWidth = {'1x', '1x'};
    paramArea.RowHeight = {'1x'};
    paramArea.Padding = [0 0 0 0];

    panelHardware = uipanel(paramArea, 'Title', '  硬件参数  ', ...
        'FontWeight', 'bold', 'BackgroundColor', COLORS.panelBg);
    panelHardware.Layout.Row = 1;
    panelHardware.Layout.Column = 1;

    hwGrid = uigridlayout(panelHardware, [5 2]);
    hwGrid.RowHeight = {35, 35, 35, 35, 50};
    hwGrid.ColumnWidth = {110, '1x'};
    hwGrid.Padding = [15 10 15 15];

    app.edS   = createInputRowWithLabel(hwGrid, 1, '灵敏度', 'V/MPa', 0.0263, 0.001, 1);
    app.edG   = createInputRowWithLabel(hwGrid, 2, '增益', 'dB', 14, 0, 80);
    app.edAtt = createInputRowWithLabel(hwGrid, 3, '衰减', 'dB', 18, 0, 80);
    % PRF 用文本框，允许初始显示 NaN；计算时再转成数值并校验
    lblPRF = uilabel(hwGrid, 'Text', '* PRF (必填) (Hz):', ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    lblPRF.Layout.Row = 4;
    lblPRF.Layout.Column = 1;
    app.edPRF = uieditfield(hwGrid, 'text', 'Value', 'NaN', 'HorizontalAlignment', 'center');
    app.edPRF.Layout.Row = 4;
    app.edPRF.Layout.Column = 2;
    app.edPRF.Tooltip = '请输入 PRF（Hz），必须大于 0；默认显示 NaN 代表尚未输入';
    app.edPRF.ValueChangedFcn = @(src, ~) onFieldModified(src);

    app.cbDynamicS = uicheckbox(hwGrid, ...
        'Text', 'NH2000 动态频响补偿 (0.5~20MHz)', ...
        'Value', true, 'FontWeight', 'bold', 'FontColor', COLORS.accent);
    app.cbDynamicS.Layout.Row = 5;
    app.cbDynamicS.Layout.Column = [1 2];

    panelCalc = uipanel(paramArea, 'Title', '  介质与计算设置  ', ...
        'FontWeight', 'bold', 'BackgroundColor', COLORS.panelBg);
    panelCalc.Layout.Row = 1;
    panelCalc.Layout.Column = 2;

    calcGrid = uigridlayout(panelCalc, [4 2]);
    calcGrid.RowHeight = {35, 35, 35, 35};
    calcGrid.ColumnWidth = {100, '1x'};
    calcGrid.Padding = [15 10 15 15];

    app.edRho = createInputRowWithLabel(calcGrid, 1, '介质密度', 'kg/m³', 1000, 100, 20000);
    app.edC   = createInputRowWithLabel(calcGrid, 2, '声速', 'm/s', 1500, 100, 5000);

    lblMaxBasis = uilabel(calcGrid, 'Text', '最大点判定:', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    lblMaxBasis.Layout.Row = 3;
    lblMaxBasis.Layout.Column = 1;

    app.ddMaxBy = uidropdown(calcGrid, ...
        'Items', {'Vpp','Ppp','Isppa','Ispta','PII'}, ...
        'Value', 'Vpp');
    app.ddMaxBy.Layout.Row = 3;
    app.ddMaxBy.Layout.Column = 2;

    lblStep1 = uilabel(calcGrid, 'Text', '数据目录:', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    lblStep1.Layout.Row = 4;
    lblStep1.Layout.Column = 1;

    app.lblFolder = uilabel(calcGrid, 'Text', '(未选择)', ...
        'HorizontalAlignment', 'left', 'FontColor', COLORS.textLight, 'WordWrap', 'on');
    app.lblFolder.Layout.Row = 4;
    app.lblFolder.Layout.Column = 2;

    app.btnArea = uigridlayout(inputMainGrid, [1 4]);
    app.btnArea.ColumnWidth = {180, 120, '1x', 220};
    app.btnArea.Padding = [10 5 10 5];

    app.btnPick = uibutton(app.btnArea, 'Text', '📂 选择文件夹', ...
        'ButtonPushedFcn', @onPickFolder, ...
        'BackgroundColor', COLORS.secondary, 'FontColor', 'w');
    app.btnPick.Layout.Row = 1;
    app.btnPick.Layout.Column = 1;

    app.btnReset = uibutton(app.btnArea, 'Text', '↺ 重置参数', ...
        'ButtonPushedFcn', @onResetParams, ...
        'BackgroundColor', [0.6 0.6 0.6], 'FontColor', 'w');
    app.btnReset.Layout.Row = 1;
    app.btnReset.Layout.Column = 2;

    app.lblStatus = uilabel(app.btnArea, 'Text', '就绪 - 请选择数据文件夹，并请输入 PRF (>0)', ...
        'HorizontalAlignment', 'center', 'FontColor', COLORS.textLight, 'FontSize', 12);
    app.lblStatus.Layout.Row = 1;
    app.lblStatus.Layout.Column = 3;

    app.btnRun = uibutton(app.btnArea, 'Text', '🚀 开始计算', ...
        'ButtonPushedFcn', @onRun, ...
        'BackgroundColor', COLORS.primary, 'FontColor', 'w', ...
        'FontSize', 14, 'FontWeight', 'bold', 'Enable', 'off');
    app.btnRun.Layout.Row = 1;
    app.btnRun.Layout.Column = 4;

    app.progressArea = uigridlayout(inputMainGrid, [1 3]);
    app.progressArea.RowHeight = {35};
    app.progressArea.ColumnWidth = {60, '1x', 80};
    app.progressArea.Padding = [10 8 10 8];
    app.progressArea.Layout.Row = 3;
    app.progressArea.Visible = 'off';

    app.lblProgressPct = uilabel(app.progressArea, 'Text', '0%', ...
        'HorizontalAlignment', 'right', 'FontWeight', 'bold', 'FontColor', COLORS.primary);
    app.lblProgressPct.Layout.Row = 1;
    app.lblProgressPct.Layout.Column = 1;

    progressContainer = uipanel(app.progressArea, 'BackgroundColor', [0.9 0.9 0.9]);
    progressContainer.Layout.Row = 1;
    progressContainer.Layout.Column = 2;
    progressContainer.BorderType = 'none';
    app.progressBarBg = progressContainer;

    app.progressBarFill = uipanel(progressContainer, 'BackgroundColor', COLORS.primary);
    app.progressBarFill.Position = [1 1 0 25];
    app.progressBarFill.BorderType = 'none';

    app.lblProgressFile = uilabel(progressContainer, 'Text', '准备处理...', ...
        'HorizontalAlignment', 'center', 'FontColor', [1 1 1], 'FontSize', 11, 'FontWeight', 'bold');
    app.lblProgressFile.Position = [0 2 500 21];

    app.btnCancel = uibutton(app.progressArea, 'Text', '⏹ 中止', ...
        'ButtonPushedFcn', @onCancelCalculation, ...
        'BackgroundColor', COLORS.accent, 'FontColor', 'w', 'FontWeight', 'bold');
    app.btnCancel.Layout.Row = 1;
    app.btnCancel.Layout.Column = 3;

    app.isCalculating = false;
    app.isCancelled = false;

    app.defaultValues = struct('S', 0.0263, 'G', 14, 'Att', 18, ...
        'rho', 1000, 'c', 1500, 'PRF', NaN, 'maxBy', 'Vpp', 'useDynamicS', true);

    % ============================================================
    % 3. 界面 2 & 3: Single Waveform & Linear
    % ============================================================
    swGrid = uigridlayout(app.tabSingle, [3, 1]);
    swGrid.RowHeight = {'1x', 80, 160};
    swGrid.Padding = [10 5 10 5];

    swPlotGrid = uigridlayout(swGrid, [1, 2]);
    swPlotGrid.Padding = [0 0 0 0];

    app.axTime = createLabeledAxes(swPlotGrid, 'Time Domain Waveform', 'Time (\mu s)', 'Voltage (mV)');
    app.axFreq = createLabeledAxes(swPlotGrid, 'Frequency Spectrum', 'Frequency (MHz)', 'Amplitude');

    swParamGrid = uigridlayout(swGrid, [2, 4]);
    swParamGrid.BackgroundColor = [0.95 0.95 0.95];
    app.lblSwPosPeak = uilabel(swParamGrid, 'Text', 'Peak Positive(mV): -', 'FontWeight', 'bold');
    app.lblSwNegPeak = uilabel(swParamGrid, 'Text', 'Peak Negative(mV): -', 'FontWeight', 'bold');
    app.lblSwVpp     = uilabel(swParamGrid, 'Text', 'Peak-to-Peak(mV): -', 'FontWeight', 'bold');
    app.lblSwVrms    = uilabel(swParamGrid, 'Text', 'RMS Voltage(mV): -', 'FontWeight', 'bold');
    app.lblSwFc      = uilabel(swParamGrid, 'Text', 'Peak-Frequency(MHz): -', 'FontWeight', 'bold');
    app.lblSwTau     = uilabel(swParamGrid, 'Text', 'IEC Pulse Duration(us): -', 'FontWeight', 'bold');
    app.lblSwIspta   = uilabel(swParamGrid, 'Text', 'Ispta(mW/cm^2): -');
    app.lblSwIsppa   = uilabel(swParamGrid, 'Text', 'Isppa(mW/cm^2): -');

    swTblGrid = uigridlayout(swGrid, [1, 2]);
    swTblGrid.Padding = [0 0 0 0];
    app.tblTime = uitable(swTblGrid, 'RowName', {'RiseTime', 'FallTime', 'Duration'}, ...
        'ColumnName', {'-6dB', '-12dB', '-20dB', '-40dB'});
    app.tblFreq = uitable(swTblGrid, 'RowName', {'Lower', 'Center', 'Upper', 'Bandwidth'}, ...
        'ColumnName', {'-3dB', '-6dB', '-12dB', '-20dB'});

    linGrid = uigridlayout(app.tabLinear, [1, 2]);
    app.axLinX = createLabeledAxes(linGrid, 'Horizontal Profile', 'X (mm)', 'Ppp (MPa)');
    app.axLinY = createLabeledAxes(linGrid, 'Vertical Profile', 'Y (mm)', 'Ppp (MPa)');

    % ============================================================
    % 4. 界面 4: 2-D Map
    % ============================================================
    t2dGrid = uigridlayout(app.tab2D, [2, 1]);
    t2dGrid.RowHeight = {'1x', 260};

    plot2dGrid = uigridlayout(t2dGrid, [1, 2]);
    plot2dGrid.Padding = [0 0 0 0];
    app.ax2D_Vpp = createLabeledAxes(plot2dGrid, '2D Vpp Map', 'X (mm)', 'Y (mm)');
    app.ax2D_Ppp = createLabeledAxes(plot2dGrid, '2D Ppp Map', 'X (mm)', 'Y (mm)');

    paramPanel = uipanel(t2dGrid, 'Title', 'Spatial & Energy Parameters (安规声场参数)', 'FontWeight', 'bold');
    ppGrid = uigridlayout(paramPanel, [1, 2]);
    ppGrid.ColumnWidth = {420, '1x'};

    areaGrid = uigridlayout(ppGrid, [2, 1]);
    areaGrid.Padding = [5 5 5 5];
    areaGrid.RowHeight = {'fit', '1x'};
    app.lblFocalCoord = uilabel(areaGrid, 'Text', 'Focal Area: (-)', 'FontWeight', 'bold');
    app.tblBeamArea = uitable(areaGrid, ...
        'RowName', {'Beam Area(mm^2)'}, ...
        'ColumnName', {'-6dB', '-12dB', '-20dB'}, ...
        'ColumnWidth', {'1x', '1x', '1x'});

    valGrid = uigridlayout(ppGrid, [6, 4]);
    valGrid.Padding = [10 5 10 5];
    valGrid.ColumnWidth = {'2.3x', 100, '2.0x', 100};
    app.lbl_Isptp   = createValRow(valGrid, 1, 1, 'Isptp (mW/cm^2)');
    app.lbl_Isptp_3 = createValRow(valGrid, 1, 3, 'Isptp,3 (mW/cm^2)');
    app.lbl_Ispta   = createValRow(valGrid, 2, 1, 'Ispta (mW/cm^2)');
    app.lbl_Ispta_3 = createValRow(valGrid, 2, 3, 'Ispta,3 (mW/cm^2)');
    app.lbl_Isppa   = createValRow(valGrid, 3, 1, 'Isppa (mW/cm^2)');
    app.lbl_Isppa_3 = createValRow(valGrid, 3, 3, 'Isppa,3 (mW/cm^2)');
    app.lbl_Isatp   = createValRow(valGrid, 4, 1, 'Isatp (mW/cm^2)');
    app.lbl_Power   = createValRow(valGrid, 4, 3, 'Power (mW)');
    app.lbl_Isata   = createValRow(valGrid, 5, 1, 'Isata (mW/cm^2)');
    app.lbl_MI      = createValRow(valGrid, 5, 3, 'Max MI (-)');
    app.lbl_Isapa   = createValRow(valGrid, 6, 1, 'Isapa (mW/cm^2)');
    app.lbl_MI_3    = createValRow(valGrid, 6, 3, 'Max MI,3 (-)');

    % ============================================================
    % 5. 界面 5: 3D Scatter
    % ============================================================
    t3dGrid = uigridlayout(app.tab3D, [1, 2]);
    app.ax3D_Vpp = create3DAxes(t3dGrid, '3D Vpp Point Cloud');
    app.ax3D_Ppp = create3DAxes(t3dGrid, '3D Ppp Point Cloud');

    % ============================================================
    % 6. 界面 6: Surface XZ
    % ============================================================
    tSurfGrid = uigridlayout(app.tabSurfXZ, [1, 2]);
    app.axSurf_Vpp = create3DAxes(tSurfGrid, 'XZ Plane Surface Vpp Plot', 'Vpp (V)');
    app.axSurf_Ppp = create3DAxes(tSurfGrid, 'XZ Plane Surface Ppp Plot', 'Ppp (MPa)');

    % ============================================================
    % 7. 界面 7: Report
    % ============================================================
    repGrid = uigridlayout(app.tabReport, [2, 1]);
    repGrid.RowHeight = {'1x', '1x'};
    app.txtReport = uitextarea(repGrid, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 12);
    app.tblReport = uitable(repGrid);

    % ============================================================
    % 8. 界面 8: 声轴对齐
    % ============================================================
    alignMain = uigridlayout(app.tabAlign, [2 1]);
    alignMain.RowHeight = {320, '1x'};
    alignMain.Padding = [12 12 12 12];

    alignTop = uigridlayout(alignMain, [1 2]);
    alignTop.ColumnWidth = {420, '1x'};
    alignTop.ColumnSpacing = 12;
    alignTop.Padding = [0 0 0 0];

    panelAlignInput = uipanel(alignTop, 'Title', '  输入数据  ', ...
        'FontWeight', 'bold', 'BackgroundColor', COLORS.panelBg);
    panelAlignInput.Layout.Row = 1;
    panelAlignInput.Layout.Column = 1;

    ag = uigridlayout(panelAlignInput, [7 3]);
    ag.RowHeight = {30, 30, 30, 30, 40, 40, '1x'};
    ag.ColumnWidth = {110, '1x', 100};
    ag.Padding = [12 12 12 12];
    ag.RowSpacing = 8;
    ag.ColumnSpacing = 8;

    uilabel(ag, 'Text', '近端X扫描:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    app.edAlignXNear = uieditfield(ag, 'text', 'Editable', 'off', 'Value', '');
    app.btnAlignXNear = uibutton(ag, 'Text', '选择文件夹', ...
        'ButtonPushedFcn', @onPickAlignXNear, 'BackgroundColor', COLORS.secondary, 'FontColor', 'w');
    app.edAlignXNear.Layout.Row = 1; app.edAlignXNear.Layout.Column = 2;
    app.btnAlignXNear.Layout.Row = 1; app.btnAlignXNear.Layout.Column = 3;

    uilabel(ag, 'Text', '远端X扫描:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    app.edAlignXFar = uieditfield(ag, 'text', 'Editable', 'off', 'Value', '');
    app.btnAlignXFar = uibutton(ag, 'Text', '选择文件夹', ...
        'ButtonPushedFcn', @onPickAlignXFar, 'BackgroundColor', COLORS.secondary, 'FontColor', 'w');
    app.edAlignXFar.Layout.Row = 2; app.edAlignXFar.Layout.Column = 2;
    app.btnAlignXFar.Layout.Row = 2; app.btnAlignXFar.Layout.Column = 3;

    uilabel(ag, 'Text', '近端Z扫描:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    app.edAlignZNear = uieditfield(ag, 'text', 'Editable', 'off', 'Value', '');
    app.btnAlignZNear = uibutton(ag, 'Text', '选择文件夹', ...
        'ButtonPushedFcn', @onPickAlignZNear, 'BackgroundColor', COLORS.secondary, 'FontColor', 'w');
    app.edAlignZNear.Layout.Row = 3; app.edAlignZNear.Layout.Column = 2;
    app.btnAlignZNear.Layout.Row = 3; app.btnAlignZNear.Layout.Column = 3;

    uilabel(ag, 'Text', '远端Z扫描:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    app.edAlignZFar = uieditfield(ag, 'text', 'Editable', 'off', 'Value', '');
    app.btnAlignZFar = uibutton(ag, 'Text', '选择文件夹', ...
        'ButtonPushedFcn', @onPickAlignZFar, 'BackgroundColor', COLORS.secondary, 'FontColor', 'w');
    app.edAlignZFar.Layout.Row = 4; app.edAlignZFar.Layout.Column = 2;
    app.btnAlignZFar.Layout.Row = 4; app.btnAlignZFar.Layout.Column = 3;

    app.btnCalcAlignX = uibutton(ag, 'Text', '计算 X方向偏转角', ...
        'ButtonPushedFcn', @onCalcAlignX, ...
        'BackgroundColor', COLORS.primary, 'FontColor', 'w', 'FontWeight', 'bold');
    app.btnCalcAlignX.Layout.Row = 5;
    app.btnCalcAlignX.Layout.Column = [1 3];

    app.btnCalcAlignZ = uibutton(ag, 'Text', '计算 Z方向偏转角', ...
        'ButtonPushedFcn', @onCalcAlignZ, ...
        'BackgroundColor', COLORS.primary, 'FontColor', 'w', 'FontWeight', 'bold');
    app.btnCalcAlignZ.Layout.Row = 6;
    app.btnCalcAlignZ.Layout.Column = [1 3];

    app.lblAlignStatus = uilabel(ag, 'Text', '请选择两组不同 Y 截面的扫描文件夹', ...
        'WordWrap', 'on', 'FontColor', COLORS.textLight, 'HorizontalAlignment', 'center');
    app.lblAlignStatus.Layout.Row = 7;
    app.lblAlignStatus.Layout.Column = [1 3];

    panelAlignRes = uipanel(alignTop, 'Title', '  计算结果  ', ...
        'FontWeight', 'bold', 'BackgroundColor', COLORS.panelBg);
    panelAlignRes.Layout.Row = 1;
    panelAlignRes.Layout.Column = 2;

    rg = uigridlayout(panelAlignRes, [6 4]);
    rg.RowHeight = {32, 32, 32, 32, 32, '1x'};
    rg.ColumnWidth = {150, '1x', 150, '1x'};
    rg.Padding = [12 12 12 12];
    rg.RowSpacing = 8;

    app.lblAlignXAngle = createValRow(rg, 1, 1, 'X方向偏转角 (deg)');
    app.lblAlignXRad   = createValRow(rg, 1, 3, 'X方向偏转角 (rad)');
    app.lblAlignXdY    = createValRow(rg, 2, 1, 'X方向 ΔY (mm)');
    app.lblAlignXdX    = createValRow(rg, 2, 3, 'X方向 ΔX (mm)');
    app.lblAlignXPeak1 = createValRow(rg, 3, 1, '近端峰值 X (mm)');
    app.lblAlignXPeak2 = createValRow(rg, 3, 3, '远端峰值 X (mm)');

    app.lblAlignZAngle = createValRow(rg, 4, 1, 'Z方向偏转角 (deg)');
    app.lblAlignZRad   = createValRow(rg, 4, 3, 'Z方向偏转角 (rad)');
    app.lblAlignZdY    = createValRow(rg, 5, 1, 'Z方向 ΔY (mm)');
    app.lblAlignZdZ    = createValRow(rg, 5, 3, 'Z方向 ΔZ (mm)');
    app.lblAlignZPeak1 = createValRow(rg, 6, 1, '近端峰值 Z (mm)');
    app.lblAlignZPeak2 = createValRow(rg, 6, 3, '远端峰值 Z (mm)');

    alignBottom = uigridlayout(alignMain, [2 2]);
    alignBottom.RowHeight = {'1x', 170};
    alignBottom.ColumnWidth = {'1x', '1x'};
    alignBottom.RowSpacing = 12;
    alignBottom.ColumnSpacing = 12;
    alignBottom.Padding = [0 0 0 0];

    app.axAlignX = createLabeledAxes(alignBottom, 'X方向对齐曲线', 'X (mm)', 'Vpp (V)');
    app.axAlignX.Layout.Row = 1;
    app.axAlignX.Layout.Column = 1;

    app.axAlignZ = createLabeledAxes(alignBottom, 'Z方向对齐曲线', 'Z (mm)', 'Vpp (V)');
    app.axAlignZ.Layout.Row = 1;
    app.axAlignZ.Layout.Column = 2;

    app.tblAlignX = uitable(alignBottom, ...
        'ColumnName', {'类型','文件夹','峰值Y(mm)','峰值X(mm)','峰值Vpp(V)','样本数'});
    app.tblAlignX.Layout.Row = 2;
    app.tblAlignX.Layout.Column = 1;

    app.tblAlignZ = uitable(alignBottom, ...
        'ColumnName', {'类型','文件夹','峰值Y(mm)','峰值Z(mm)','峰值Vpp(V)','样本数'});
    app.tblAlignZ.Layout.Row = 2;
    app.tblAlignZ.Layout.Column = 2;

    app.folder = "";
    app.alignXNearFolder = "";
    app.alignXFarFolder  = "";
    app.alignZNearFolder = "";
    app.alignZFarFolder  = "";

    function onPickFolder(~,~)
        f = uigetdir(pwd);
        if isequal(f, 0), return; end
        app.folder = char(f);
        if length(app.folder) > 40
            app.lblFolder.Text = ['...' app.folder(end-36:end)];
        else
            app.lblFolder.Text = app.folder;
        end
        app.lblFolder.FontColor = COLORS.text;
        app.lblFolder.Tooltip = app.folder;
        app.lblStatus.Text = sprintf('已选择: %d 个文件', countXlsxFiles(app.folder));
        app.lblStatus.FontColor = COLORS.secondary;
        app.btnRun.Enable = 'on';
    end

    function onPickAlignXNear(~,~)
        f = uigetdir(pwd, '选择近端 X 扫描文件夹');
        if isequal(f,0), return; end
        app.alignXNearFolder = string(f);
        app.edAlignXNear.Value = char(app.alignXNearFolder);
        app.edAlignXNear.Tooltip = char(app.alignXNearFolder);
        app.lblAlignStatus.Text = sprintf('已选择近端X扫描: %d 个文件', countXlsxFiles(char(app.alignXNearFolder)));
        app.lblAlignStatus.FontColor = COLORS.secondary;
    end

    function onPickAlignXFar(~,~)
        f = uigetdir(pwd, '选择远端 X 扫描文件夹');
        if isequal(f,0), return; end
        app.alignXFarFolder = string(f);
        app.edAlignXFar.Value = char(app.alignXFarFolder);
        app.edAlignXFar.Tooltip = char(app.alignXFarFolder);
        app.lblAlignStatus.Text = sprintf('已选择远端X扫描: %d 个文件', countXlsxFiles(char(app.alignXFarFolder)));
        app.lblAlignStatus.FontColor = COLORS.secondary;
    end

    function onPickAlignZNear(~,~)
        f = uigetdir(pwd, '选择近端 Z 扫描文件夹');
        if isequal(f,0), return; end
        app.alignZNearFolder = string(f);
        app.edAlignZNear.Value = char(app.alignZNearFolder);
        app.edAlignZNear.Tooltip = char(app.alignZNearFolder);
        app.lblAlignStatus.Text = sprintf('已选择近端Z扫描: %d 个文件', countXlsxFiles(char(app.alignZNearFolder)));
        app.lblAlignStatus.FontColor = COLORS.secondary;
    end

    function onPickAlignZFar(~,~)
        f = uigetdir(pwd, '选择远端 Z 扫描文件夹');
        if isequal(f,0), return; end
        app.alignZFarFolder = string(f);
        app.edAlignZFar.Value = char(app.alignZFarFolder);
        app.edAlignZFar.Tooltip = char(app.alignZFarFolder);
        app.lblAlignStatus.Text = sprintf('已选择远端Z扫描: %d 个文件', countXlsxFiles(char(app.alignZFarFolder)));
        app.lblAlignStatus.FontColor = COLORS.secondary;
    end

    function n = countXlsxFiles(folder)
        files = dir(fullfile(folder, '*.xlsx'));
        files = files(~contains(string({files.name}), ["Result","Report","Ispta"]));
        n = numel(files);
    end

    function onResetParams(~,~)
        app.edS.Value = app.defaultValues.S;
        app.edG.Value = app.defaultValues.G;
        app.edAtt.Value = app.defaultValues.Att;
        app.edRho.Value = app.defaultValues.rho;
        app.edC.Value = app.defaultValues.c;
        app.edPRF.Value = 'NaN';
        app.ddMaxBy.Value = app.defaultValues.maxBy;
        app.cbDynamicS.Value = app.defaultValues.useDynamicS;
        resetFieldColor(app.edS);   resetFieldColor(app.edG);   resetFieldColor(app.edAtt);
        resetFieldColor(app.edRho); resetFieldColor(app.edC);   resetFieldColor(app.edPRF);
        app.lblStatus.Text = '参数已重置为默认值；请重新输入 PRF (>0)';
        app.lblStatus.FontColor = COLORS.secondary;
    end

    function [params, ok] = getCurrentParams()
        params.S = app.edS.Value;
        params.G = app.edG.Value;
        params.Att = app.edAtt.Value;
        params.rho = app.edRho.Value;
        params.c = app.edC.Value;
        params.maxBy = char(app.ddMaxBy.Value);
        params.useDynamicS = app.cbDynamicS.Value;
        params.manualPRF = NaN;
        ok = false;

        prfVal = str2double(string(app.edPRF.Value));
        if isnan(prfVal) || prfVal <= 0
            uialert(app.fig, '请输入 PRF，且必须大于 0。', 'PRF 输入提醒', 'Icon', 'warning');
            if isfield(app, 'lblStatus') && isvalid(app.lblStatus)
                app.lblStatus.Text = '请输入 PRF (>0)';
                app.lblStatus.FontColor = COLORS.accent;
            end
            return;
        end

        params.manualPRF = prfVal;
        ok = true;

        if isfield(app, 'lblStatus') && isvalid(app.lblStatus)
            app.lblStatus.Text = sprintf('PRF 有效：%.6f Hz（将按手动输入值计算）', params.manualPRF);
            app.lblStatus.FontColor = COLORS.secondary;
        end
    end

    function onCalcAlignX(~,~)
        try
            if strlength(app.alignXNearFolder) == 0 || strlength(app.alignXFarFolder) == 0
                error('请先选择近端和远端 X 扫描文件夹');
            end
            [params, ok] = getCurrentParams();
            if ~ok
                app.lblAlignStatus.Text = '请输入 PRF (>0)';
                app.lblAlignStatus.FontColor = COLORS.accent;
                return;
            end
            params.maxBy = 'Vpp';
            app.lblAlignStatus.Text = sprintf('PRF 有效：%.6f Hz（按手动输入值计算）', params.manualPRF);
            app.lblAlignStatus.FontColor = COLORS.secondary;
            app.lblAlignStatus.Text = sprintf('PRF 有效：%.6f Hz（按手动输入值计算）', params.manualPRF);
            app.lblAlignStatus.FontColor = COLORS.secondary;

            nearInfo = analyzeAlignFolder(char(app.alignXNearFolder), params, 'X');
            farInfo  = analyzeAlignFolder(char(app.alignXFarFolder),  params, 'X');
            out      = calcTiltFromTwoLines(nearInfo, farInfo, 'X');

            app.lblAlignXAngle.Value = sprintf('%.6f', out.theta_deg);
            app.lblAlignXRad.Value   = sprintf('%.8f', out.theta_rad);
            app.lblAlignXdY.Value    = sprintf('%.6f', out.dY);
            app.lblAlignXdX.Value    = sprintf('%.6f', out.dCoord);
            app.lblAlignXPeak1.Value = sprintf('%.6f', out.coord1);
            app.lblAlignXPeak2.Value = sprintf('%.6f', out.coord2);

            app.tblAlignX.Data = {
                '近端', char(app.alignXNearFolder), nearInfo.peakY, nearInfo.peakX, nearInfo.peakVpp, height(nearInfo.result);
                '远端', char(app.alignXFarFolder),  farInfo.peakY,  farInfo.peakX,  farInfo.peakVpp,  height(farInfo.result)
            };

            cla(app.axAlignX);
            plot(app.axAlignX, nearInfo.axisVals, nearInfo.axisMetric, '-o', 'LineWidth', 1.2, 'MarkerSize', 5);
            hold(app.axAlignX, 'on');
            plot(app.axAlignX, farInfo.axisVals, farInfo.axisMetric, '-s', 'LineWidth', 1.2, 'MarkerSize', 5);
            plot(app.axAlignX, nearInfo.peakX, nearInfo.peakVpp, 'rp', 'MarkerSize', 12, 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
            plot(app.axAlignX, farInfo.peakX, farInfo.peakVpp, 'mp', 'MarkerSize', 12, 'LineWidth', 1.5, 'MarkerFaceColor', 'm');
            xlabel(app.axAlignX, 'X (mm)');
            ylabel(app.axAlignX, 'Vpp (V)');
            title(app.axAlignX, sprintf('X方向对齐曲线 | 偏转角 = %.6f°', out.theta_deg));
            legend(app.axAlignX, {'近端曲线','远端曲线','近端峰值','远端峰值'}, 'Location', 'best');
            grid(app.axAlignX, 'on');
            hold(app.axAlignX, 'off');

            app.lblAlignStatus.Text = 'X方向偏转角计算完成';
            app.lblAlignStatus.FontColor = COLORS.secondary;
            app.tg.SelectedTab = app.tabAlign;

        catch ME
            uialert(app.fig, ME.message, 'X方向偏转角计算错误', 'Icon', 'error');
            app.lblAlignStatus.Text = 'X方向偏转角计算失败';
            app.lblAlignStatus.FontColor = COLORS.accent;
        end
    end

    function onCalcAlignZ(~,~)
        try
            if strlength(app.alignZNearFolder) == 0 || strlength(app.alignZFarFolder) == 0
                error('请先选择近端和远端 Z 扫描文件夹');
            end
            params = getCurrentParams();
            params.maxBy = 'Vpp';

            nearInfo = analyzeAlignFolder(char(app.alignZNearFolder), params, 'Z');
            farInfo  = analyzeAlignFolder(char(app.alignZFarFolder),  params, 'Z');
            out      = calcTiltFromTwoLines(nearInfo, farInfo, 'Z');

            app.lblAlignZAngle.Value = sprintf('%.6f', out.theta_deg);
            app.lblAlignZRad.Value   = sprintf('%.8f', out.theta_rad);
            app.lblAlignZdY.Value    = sprintf('%.6f', out.dY);
            app.lblAlignZdZ.Value    = sprintf('%.6f', out.dCoord);
            app.lblAlignZPeak1.Value = sprintf('%.6f', out.coord1);
            app.lblAlignZPeak2.Value = sprintf('%.6f', out.coord2);

            app.tblAlignZ.Data = {
                '近端', char(app.alignZNearFolder), nearInfo.peakY, nearInfo.peakZ, nearInfo.peakVpp, height(nearInfo.result);
                '远端', char(app.alignZFarFolder),  farInfo.peakY,  farInfo.peakZ,  farInfo.peakVpp,  height(farInfo.result)
            };

            cla(app.axAlignZ);
            plot(app.axAlignZ, nearInfo.axisVals, nearInfo.axisMetric, '-o', 'LineWidth', 1.2, 'MarkerSize', 5);
            hold(app.axAlignZ, 'on');
            plot(app.axAlignZ, farInfo.axisVals, farInfo.axisMetric, '-s', 'LineWidth', 1.2, 'MarkerSize', 5);
            plot(app.axAlignZ, nearInfo.peakZ, nearInfo.peakVpp, 'rp', 'MarkerSize', 12, 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
            plot(app.axAlignZ, farInfo.peakZ, farInfo.peakVpp, 'mp', 'MarkerSize', 12, 'LineWidth', 1.5, 'MarkerFaceColor', 'm');
            xlabel(app.axAlignZ, 'Z (mm)');
            ylabel(app.axAlignZ, 'Vpp (V)');
            title(app.axAlignZ, sprintf('Z方向对齐曲线 | 偏转角 = %.6f°', out.theta_deg));
            legend(app.axAlignZ, {'近端曲线','远端曲线','近端峰值','远端峰值'}, 'Location', 'best');
            grid(app.axAlignZ, 'on');
            hold(app.axAlignZ, 'off');

            app.lblAlignStatus.Text = 'Z方向偏转角计算完成';
            app.lblAlignStatus.FontColor = COLORS.secondary;
            app.tg.SelectedTab = app.tabAlign;

        catch ME
            uialert(app.fig, ME.message, 'Z方向偏转角计算错误', 'Icon', 'error');
            app.lblAlignStatus.Text = 'Z方向偏转角计算失败';
            app.lblAlignStatus.FontColor = COLORS.accent;
        end
    end

    function resetFieldColor(ed)
        ed.BackgroundColor = [1 1 1];
    end

    function onFieldModified(src, ~)
        src.BackgroundColor = [1 0.95 0.8];
        if isequal(src, app.edPRF)
            prfVal = str2double(string(src.Value));
            if isnan(prfVal) || prfVal <= 0
                app.lblStatus.Text = '请输入 PRF (>0)';
                app.lblStatus.FontColor = COLORS.accent;
            else
                app.lblStatus.Text = sprintf('PRF 有效：%.6f Hz（将按手动输入值计算）', prfVal);
                app.lblStatus.FontColor = COLORS.secondary;
            end
        end
    end

    function setupFieldValidation(ed, minVal, maxVal)
        ed.UserData.minVal = minVal;
        ed.UserData.maxVal = maxVal;
        ed.ValueChangedFcn = @(src, evt) handleValidatedFieldChanged(src, evt);
    end

    function handleValidatedFieldChanged(src, ~)
        onFieldModified(src);
        minVal = -inf;
        maxVal = inf;
        if isstruct(src.UserData)
            if isfield(src.UserData, 'minVal'), minVal = src.UserData.minVal; end
            if isfield(src.UserData, 'maxVal'), maxVal = src.UserData.maxVal; end
        end
        validateNumericField(src, minVal, maxVal);
    end

    function validateNumericField(src, minVal, maxVal)
        val = src.Value;
        if val < minVal || val > maxVal
            src.BackgroundColor = [1 0.85 0.85];
            uialert(app.fig, sprintf('输入值 %.4f 超出有效范围 [%.4f, %.4f]', val, minVal, maxVal), ...
                '输入错误', 'Icon', 'warning');
        else
            src.BackgroundColor = [1 0.95 0.8];
        end
    end

    function ed = createInputRowWithLabel(grid, r, txt, unit, val, minVal, maxVal)
        if nargin < 6, minVal = -inf; end
        if nargin < 7, maxVal = inf; end
        lbl = uilabel(grid, 'Text', sprintf('%s (%s):', txt, unit), ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold');
        lbl.Layout.Row = r;
        lbl.Layout.Column = 1;
        ed = uieditfield(grid, 'numeric', 'Value', val, 'HorizontalAlignment', 'center');
        ed.Layout.Row = r;
        ed.Layout.Column = 2;
        ed.Tooltip = sprintf('%s (%s) | 范围: %.4g ~ %.4g', txt, unit, minVal, maxVal);
        ed.ValueChangedFcn = @(src, ~) onFieldModified(src);
        if isfinite(minVal) || isfinite(maxVal)
            setupFieldValidation(ed, minVal, maxVal);
        end
    end

    function valField = createValRow(grid, r, c, txt)
        lbl = uilabel(grid, 'Text', txt, 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
        lbl.Layout.Row = r;
        lbl.Layout.Column = c;
        valField = uieditfield(grid, 'text', 'Value', '0', 'Editable', 'off', ...
            'BackgroundColor', [0.98 0.98 0.98]);
        valField.Layout.Row = r;
        valField.Layout.Column = c+1;
    end

    function ax = createLabeledAxes(parent, titleStr, xlabelStr, ylabelStr)
        ax = uiaxes(parent);
        title(ax, titleStr);
        xlabel(ax, xlabelStr);
        ylabel(ax, ylabelStr);
        grid(ax, 'on');
    end

    function ax = create3DAxes(parent, titleStr, zlabelStr)
        if nargin < 3
            zlabelStr = 'Z Depth (mm)';
        end
        ax = uiaxes(parent);
        title(ax, titleStr);
        xlabel(ax, 'X (mm)');
        ylabel(ax, 'Y (mm)');
        zlabel(ax, zlabelStr);
        view(ax, 3);
        grid(ax, 'on');
    end

    function onRun(~,~)
        if isempty(app.folder)
            uialert(app.fig, '请先选择数据文件夹', '提示', 'Icon', 'info');
            return;
        end

        [params, ok] = getCurrentParams();
        if ~ok
            return;
        end

        app.lblStatus.Text = sprintf('PRF 有效：%.6f Hz（将按手动输入值计算）', params.manualPRF);
        app.lblStatus.FontColor = COLORS.secondary;

        app.isCalculating = true;
        app.isCancelled = false;

        app.btnArea.Visible = 'off';
        app.progressArea.Visible = 'on';
        app.progressBarFill.Position(3) = 0;
        app.lblProgressPct.Text = '0%';
        app.lblProgressFile.Text = '准备处理...';
        app.lblStatus.Text = '正在处理数据...';
        drawnow;

        try
            [result, rm, bestWave, maps, repStr, acst] = analyzeEngine(app.folder, params, @updateProgress, @checkCancelled);

            cla(app.axTime);
            plot(app.axTime, bestWave.t * 1e6, bestWave.v * 1000, 'b', 'LineWidth', 1.2);
            if isfield(bestWave, 't_start') && isfield(bestWave, 't_end') && (bestWave.t_start ~= 0 || bestWave.t_end ~= 0)
                hold(app.axTime, 'on');
                xline(app.axTime, bestWave.t_start * 1e6, 'r--', 'LineWidth', 1.5);
                xline(app.axTime, bestWave.t_end * 1e6, 'r--', 'LineWidth', 1.5);
                if isfield(bestWave, 'thresh') && bestWave.thresh > 0
                    yline(app.axTime, bestWave.thresh * 1000, 'g--', 'LineWidth', 1.5);
                    yline(app.axTime, -bestWave.thresh * 1000, 'g--', 'LineWidth', 1.5);
                end
                hold(app.axTime, 'off');
            end
            xlabel(app.axTime, 'Time (\mu s)');
            ylabel(app.axTime, 'Voltage (mV)');
            grid(app.axTime, 'on');
            title(app.axTime, 'Time Domain Waveform');

            cla(app.axFreq);
            plot(app.axFreq, bestWave.f, bestWave.fft, 'b', 'LineWidth', 1.0);
            hold(app.axFreq, 'on');

            if isfield(bestWave, 'fft_smooth') && ~isempty(bestWave.fft_smooth) ...
                    && numel(bestWave.fft_smooth) == numel(bestWave.f)
                fft_smooth_disp = bestWave.fft_smooth;
            else
                fft_smooth_disp = smoothdata(bestWave.fft, 'movmean', 10);
            end
            plot(app.axFreq, bestWave.f, fft_smooth_disp, 'r', 'LineWidth', 1.8);

            legend_items = {'Raw Spectrum', 'Smoothed Spectrum'};
            if isfield(bestWave, 'Fc') && ~isempty(bestWave.Fc) && isfinite(bestWave.Fc) && bestWave.Fc > 0
                y_fc = interp1(bestWave.f, fft_smooth_disp, bestWave.Fc, 'linear', 'extrap');
                xline(app.axFreq, bestWave.Fc, 'k--', sprintf('Fc = %.4f MHz', bestWave.Fc), ...
                    'LineWidth', 1.5, 'LabelVerticalAlignment', 'middle', 'LabelOrientation', 'horizontal');
                plot(app.axFreq, bestWave.Fc, y_fc, 'ro', 'MarkerSize', 7, 'LineWidth', 1.5, 'MarkerFaceColor', 'r');
                legend_items = {'Raw Spectrum', 'Smoothed Spectrum', 'Center Frequency'};
            end
            hold(app.axFreq, 'off');
            xlabel(app.axFreq, 'Frequency (MHz)');
            ylabel(app.axFreq, 'Amplitude');
            grid(app.axFreq, 'on');
            xlim(app.axFreq, [0 max(bestWave.f)]);
            title(app.axFreq, 'Frequency Spectrum');
            legend(app.axFreq, legend_items, 'Location', 'best');

            app.lblSwPosPeak.Text = sprintf('Peak Positive(mV): %.1f', bestWave.v_pos * 1000);
            app.lblSwNegPeak.Text = sprintf('Peak Negative(mV): %.1f', bestWave.v_neg * 1000);
            app.lblSwVpp.Text     = sprintf('Peak-to-Peak(mV): %.1f', bestWave.Vpp * 1000);
            app.lblSwVrms.Text    = sprintf('RMS Voltage(mV): %.2f', bestWave.Vrms * 1000);
            app.lblSwFc.Text      = sprintf('Peak-Frequency(MHz): %.4f', bestWave.Fc);
            app.lblSwTau.Text     = sprintf('IEC Pulse Duration(us): %.2f', bestWave.Tau);
            app.lblSwIspta.Text   = sprintf('Ispta(mW/cm^2): %.2f', bestWave.Ispta / 10);
            app.lblSwIsppa.Text   = sprintf('Isppa(mW/cm^2): %.2f', bestWave.Isppa / 10);

            app.tblTime.Data = round(bestWave.t_data, 4);
            app.tblFreq.Data = round(bestWave.f_data, 4);

            cla(app.axLinX); cla(app.axLinY); cla(app.ax2D_Vpp); cla(app.ax2D_Ppp);
            cla(app.ax3D_Vpp); cla(app.ax3D_Ppp); cla(app.axSurf_Vpp); cla(app.axSurf_Ppp);

            % 1D 数据也要画一维切面：哪个轴在变化，就画哪个轴
            nx_plot = numel(unique(result.X));
            ny_plot = numel(unique(result.Y));
            nz_plot = numel(unique(result.Z));

            if ~(maps.is2D || maps.is3D)
                if nx_plot > 1
                    result1d = sortrows(result, 'X');
                    plot(app.axLinX, result1d.X, result1d.Ppp, '-o', 'LineWidth', 1.5, 'Color', COLORS.primary);
                    xlabel(app.axLinX, 'X (mm)');
                    ylabel(app.axLinX, 'Ppp (MPa)');
                    title(app.axLinX, 'X Axis 1D Profile');
                    grid(app.axLinX, 'on');

                    cla(app.axLinY);
                    text(app.axLinY, 0.5, 0.5, '当前为 X 轴一维数据', 'Units', 'normalized', ...
                        'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', COLORS.textLight);
                    axis(app.axLinY, 'off');

                elseif ny_plot > 1
                    result1d = sortrows(result, 'Y');
                    cla(app.axLinX);
                    text(app.axLinX, 0.5, 0.5, '当前未提供 X 轴一维数据', 'Units', 'normalized', ...
                        'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', COLORS.textLight);
                    axis(app.axLinX, 'off');

                    plot(app.axLinY, result1d.Y, result1d.Ppp, '-o', 'LineWidth', 1.5, 'Color', COLORS.primary);
                    xlabel(app.axLinY, 'Y (mm)');
                    ylabel(app.axLinY, 'Ppp (MPa)');
                    title(app.axLinY, 'Y Axis 1D Profile');
                    grid(app.axLinY, 'on');

                elseif nz_plot > 1
                    cla(app.axLinX);
                    text(app.axLinX, 0.5, 0.5, '当前未提供 X 轴一维数据', 'Units', 'normalized', ...
                        'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', COLORS.textLight);
                    axis(app.axLinX, 'off');

                    result1d = sortrows(result, 'Z');
                    plot(app.axLinY, result1d.Z, result1d.Ppp, '-o', 'LineWidth', 1.5, 'Color', COLORS.primary);
                    xlabel(app.axLinY, 'Z (mm)');
                    ylabel(app.axLinY, 'Ppp (MPa)');
                    title(app.axLinY, 'Z Axis 1D Profile');
                    grid(app.axLinY, 'on');
                end
            else
                plot(app.axLinX, maps.As, maps.Mat_ppp(maps.bestR, :), '-o', 'LineWidth', 1.5, 'Color', COLORS.primary);
                xlabel(app.axLinX, [maps.xl ' (mm)']);
                ylabel(app.axLinX, 'Ppp (MPa)');
                grid(app.axLinX, 'on');
                title(app.axLinX, 'Horizontal Profile');

                plot(app.axLinY, maps.Bs, maps.Mat_ppp(:, maps.bestC), '-o', 'LineWidth', 1.5, 'Color', COLORS.primary);
                xlabel(app.axLinY, [maps.yl ' (mm)']);
                ylabel(app.axLinY, 'Ppp (MPa)');
                grid(app.axLinY, 'on');
                title(app.axLinY, 'Vertical Profile');

                if maps.is3D
                    [~, y_idx] = ismember(rm.Y, maps.Ys);
                    xz_Vpp = squeeze(maps.Mat3D_vpp(y_idx, :, :))';
                    xz_Ppp = squeeze(maps.Mat3D_ppp(y_idx, :, :))';

                    imagesc(app.ax2D_Vpp, [min(maps.Xs) max(maps.Xs)], [min(maps.Zs) max(maps.Zs)], xz_Vpp);
                    axis(app.ax2D_Vpp, 'tight', 'xy'); colormap(app.ax2D_Vpp, jet); colorbar(app.ax2D_Vpp);
                    xlabel(app.ax2D_Vpp, 'X (mm)'); ylabel(app.ax2D_Vpp, 'Depth Z (mm)');
                    title(app.ax2D_Vpp, sprintf('XZ Profile at Y=%.2f', rm.Y));

                    imagesc(app.ax2D_Ppp, [min(maps.Xs) max(maps.Xs)], [min(maps.Zs) max(maps.Zs)], xz_Ppp);
                    axis(app.ax2D_Ppp, 'tight', 'xy'); colormap(app.ax2D_Ppp, jet); colorbar(app.ax2D_Ppp);
                    xlabel(app.ax2D_Ppp, 'X (mm)'); ylabel(app.ax2D_Ppp, 'Depth Z (mm)');
                    title(app.ax2D_Ppp, sprintf('XZ Profile at Y=%.2f', rm.Y));
                else
                    imagesc(app.ax2D_Vpp, [min(maps.As) max(maps.As)], [min(maps.Bs) max(maps.Bs)], maps.Mat_vpp);
                    axis(app.ax2D_Vpp, 'equal', 'tight', 'xy'); colormap(app.ax2D_Vpp, jet); colorbar(app.ax2D_Vpp);
                    xlabel(app.ax2D_Vpp, maps.xl); ylabel(app.ax2D_Vpp, maps.yl); title(app.ax2D_Vpp, 'Vpp 2D Map');

                    imagesc(app.ax2D_Ppp, [min(maps.As) max(maps.As)], [min(maps.Bs) max(maps.Bs)], maps.Mat_ppp);
                    axis(app.ax2D_Ppp, 'equal', 'tight', 'xy'); colormap(app.ax2D_Ppp, jet); colorbar(app.ax2D_Ppp);
                    xlabel(app.ax2D_Ppp, maps.xl); ylabel(app.ax2D_Ppp, maps.yl); title(app.ax2D_Ppp, 'Ppp 2D Map');
                end

                app.lblFocalCoord.Text = sprintf('Focal Coord (mm): X=%.2f, Y=%.2f, Z=%.2f', rm.X, rm.Y, rm.Z);
                app.tblBeamArea.Data = {formatSci(acst.area_6, 2), formatSci(acst.area_12, 2), formatSci(acst.area_20, 2)};
                app.lbl_Isptp.Value = formatSci(acst.Isptp, 2); app.lbl_Isptp_3.Value = formatSci(acst.Isptp_3, 2);
                app.lbl_Ispta.Value = formatSci(acst.Ispta, 2); app.lbl_Ispta_3.Value = formatSci(acst.Ispta_3, 2);
                app.lbl_Isppa.Value = formatSci(acst.Isppa, 2); app.lbl_Isppa_3.Value = formatSci(acst.Isppa_3, 2);
                app.lbl_Isatp.Value = formatSci(acst.Isatp, 2); app.lbl_Power.Value   = formatSci(acst.Power_mW, 2);
                app.lbl_Isata.Value = formatSci(acst.Isata, 2); app.lbl_MI.Value      = formatSci(acst.MI, 3);
                app.lbl_Isapa.Value = formatSci(acst.Isapa, 2); app.lbl_MI_3.Value    = formatSci(acst.MI_3, 3);

                if maps.is3D
                    scatter3(app.ax3D_Vpp, result.X, result.Y, result.Z, 40, result.Vpp, 'filled', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.8);
                    colormap(app.ax3D_Vpp, jet); colorbar(app.ax3D_Vpp);
                    xlabel(app.ax3D_Vpp, 'X (mm)'); ylabel(app.ax3D_Vpp, 'Y (mm)'); zlabel(app.ax3D_Vpp, 'Z Depth (mm)');
                    view(app.ax3D_Vpp, 3); grid(app.ax3D_Vpp, 'on'); axis(app.ax3D_Vpp, 'tight');
                    title(app.ax3D_Vpp, '3D Vpp Point Cloud');

                    scatter3(app.ax3D_Ppp, result.X, result.Y, result.Z, 40, result.Ppp, 'filled', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.8);
                    colormap(app.ax3D_Ppp, jet); colorbar(app.ax3D_Ppp);
                    xlabel(app.ax3D_Ppp, 'X (mm)'); ylabel(app.ax3D_Ppp, 'Y (mm)'); zlabel(app.ax3D_Ppp, 'Z Depth (mm)');
                    view(app.ax3D_Ppp, 3); grid(app.ax3D_Ppp, 'on'); axis(app.ax3D_Ppp, 'tight');
                    title(app.ax3D_Ppp, '3D Ppp Point Cloud');
                end

                if maps.is3D
                    [~, y_idx] = ismember(rm.Y, maps.Ys);
                    xz_surf_Vpp = squeeze(maps.Mat3D_vpp(y_idx, :, :))';
                    xz_surf_Ppp = squeeze(maps.Mat3D_ppp(y_idx, :, :))';
                    x_surf_lbl = 'X (mm)'; y_surf_lbl = 'Z Depth (mm)';
                    x_surf_data = maps.Xs; y_surf_data = maps.Zs;
                else
                    xz_surf_Vpp = maps.Mat_vpp;
                    xz_surf_Ppp = maps.Mat_ppp;
                    x_surf_lbl = [maps.xl ' (mm)']; y_surf_lbl = [maps.yl ' (mm)'];
                    x_surf_data = maps.As; y_surf_data = maps.Bs;
                end

                surf(app.axSurf_Vpp, x_surf_data, y_surf_data, xz_surf_Vpp, 'EdgeColor', 'none');
                shading(app.axSurf_Vpp, 'interp'); colormap(app.axSurf_Vpp, jet); colorbar(app.axSurf_Vpp);
                xlabel(app.axSurf_Vpp, x_surf_lbl); ylabel(app.axSurf_Vpp, y_surf_lbl); zlabel(app.axSurf_Vpp, 'Vpp (V)');
                title(app.axSurf_Vpp, sprintf('XZ Plane Surface at Y=%.2f', rm.Y));
                view(app.axSurf_Vpp, 3); grid(app.axSurf_Vpp, 'on'); axis(app.axSurf_Vpp, 'tight');

                surf(app.axSurf_Ppp, x_surf_data, y_surf_data, xz_surf_Ppp, 'EdgeColor', 'none');
                shading(app.axSurf_Ppp, 'interp'); colormap(app.axSurf_Ppp, jet); colorbar(app.axSurf_Ppp);
                xlabel(app.axSurf_Ppp, x_surf_lbl); ylabel(app.axSurf_Ppp, y_surf_lbl); zlabel(app.axSurf_Ppp, 'Ppp (MPa)');
                title(app.axSurf_Ppp, sprintf('XZ Plane Surface at Y=%.2f', rm.Y));
                view(app.axSurf_Ppp, 3); grid(app.axSurf_Ppp, 'on'); axis(app.axSurf_Ppp, 'tight');
            end

            app.txtReport.Value = repStr;
            app.tblReport.Data = result;
            app.tblReport.ColumnName = result.Properties.VariableNames;

            if maps.is2D || maps.is3D
                app.tg.SelectedTab = app.tab2D;
                app.lblStatus.Text = sprintf('计算完成: %dD 数据 (%d 个点)', 2+maps.is3D, height(result));
            else
                app.tg.SelectedTab = app.tabLinear;
                app.lblStatus.Text = sprintf('计算完成: 1D 数据 (%d 个点)，已绘制对应轴的一维切面', height(result));
            end
            app.lblStatus.FontColor = COLORS.secondary;

        catch ME
            if app.isCancelled
                app.lblStatus.Text = '计算已中止';
                app.lblStatus.FontColor = COLORS.accent;
            else
                uialert(app.fig, ME.message, '计算错误', 'Icon', 'error');
                app.lblStatus.Text = '计算失败';
                app.lblStatus.FontColor = COLORS.accent;
            end
        end

        app.isCalculating = false;
        app.btnCancel.Enable = 'on';
        app.progressArea.Visible = 'off';
        app.btnArea.Visible = 'on';
        app.btnRun.Text = '🚀 开始计算';
        app.btnRun.Enable = 'on';
    end

    function updateProgress(progressPct, filename)
        bgWidth = app.progressBarBg.Position(3);
        barWidth = max(1, round(progressPct / 100 * bgWidth));
        app.progressBarFill.Position(3) = barWidth;
        app.lblProgressPct.Text = sprintf('%.0f%%', progressPct);
        if nargin > 1 && ~isempty(filename)
            if strlength(string(filename)) > 50
                txt = char(string(filename));
                app.lblProgressFile.Text = [txt(1:47) '...'];
            else
                app.lblProgressFile.Text = char(string(filename));
            end
        end
        drawnow limitrate;
    end

    function isCancelled = checkCancelled()
        isCancelled = app.isCancelled;
    end

    function onCancelCalculation(~, ~)
        if app.isCalculating
            app.isCancelled = true;
            app.lblStatus.Text = '正在中止...';
            app.lblProgressFile.Text = '等待当前文件处理完成...';
            app.btnCancel.Enable = 'off';
            drawnow;
        end
    end

    function str = formatSci(val, prec)
        if nargin < 2, prec = 2; end
        if isnan(val) || val == 0
            str = num2str(val);
            return;
        end
        if abs(val) >= 1000 || abs(val) < 0.01
            s = sprintf('%.4e', val);
            tokens = regexp(s, '^(-?\d+\.\d+)e([+-]\d+)$', 'tokens', 'once');
            if ~isempty(tokens)
                str = sprintf(sprintf('%%.%df x 10^%%d', prec), str2double(tokens{1}), str2double(tokens{2}));
            else
                str = num2str(val);
            end
        else
            str = sprintf(sprintf('%%.%df', prec), val);
        end
    end
end

% ============================================================
% 核心分析引擎
% ============================================================
function [result, rm, bestWave, maps, repStr, acst] = analyzeEngine(dataFolder, params, progressCallback, cancelCallback)
    G = params.G;
    Att = params.Att;
    Zac = params.rho * params.c;

    curve_F = [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, ...
               11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0];
    curve_S = [0.0214, 0.0243, 0.0263, 0.0260, 0.0265, 0.0247, 0.0224, ...
               0.0207, 0.0192, 0.0181, 0.0170, 0.0151, 0.0132, 0.0117, ...
               0.0138, 0.0151, 0.0166, 0.0203, 0.0221, 0.0233, 0.0245];

    files = dir(fullfile(dataFolder, '*.xlsx'));
    files = files(~contains(string({files.name}), ["Result","Report","Ispta"]));
    if isempty(files), error('没有找到波形 Excel 文件。'); end

    X_l=[]; Y_l=[]; Z_l=[]; Fc_l=[]; Tau_l=[]; Vpp_l=[]; Vrms_l=[];
    Ppp_l=[]; Prms_l=[]; PII_l=[]; Isppa_l=[]; Ispta_l=[]; Isptp_l=[]; Pneg_l=[]; fnames=strings(0,1);
    global_PRF=NaN; prf_source="UNKNOWN"; max_crit = -inf; bestWave = struct();
    failedFiles = strings(0,1); failedReasons = strings(0,1);

    for k = 1:numel(files)
        if ~isempty(cancelCallback) && cancelCallback()
            error('用户取消了计算');
        end

        progressPct = (k - 1) / numel(files) * 100;
        if ~isempty(progressCallback)
            progressCallback(progressPct, sprintf('正在处理: %s (%d/%d)', files(k).name, k, numel(files)));
        end

        fpath = fullfile(files(k).folder, files(k).name);
        try
            try
                m = readtable(fpath,'Sheet','元数据');
                [X,Y,Z,Excel_PRF] = getMeta(m);
            catch
                X = NaN; Y = NaN; Z = NaN; Excel_PRF = NaN;
            end
            if isnan(X)
                [X,Y,Z] = getXYZName(files(k).name);
                Excel_PRF = NaN;
            end

            if ~isnan(params.manualPRF) && params.manualPRF > 0
                PRF = params.manualPRF;
                global_PRF = PRF;
                prf_source = "MANUAL";
            else
                error('PRF 无效：请在界面中输入大于 0 的 PRF。');
            end

            if isnan(X)
                error('无法从元数据或文件名中解析 X/Y/Z 坐标');
            end

            T = readtable(fpath,'Sheet','波形数据');
            t = T{:,1};
            v = T{:,2};
            idx = ~isnan(t) & ~isnan(v);
            t = t(idx);
            v = v(idx);

            if isempty(v)
                error('波形数据为空');
            end
            if numel(t) < 2 || numel(v) < 2
                error('波形数据点数不足，至少需要 2 个采样点');
            end

            dt = abs(t(2)-t(1));
            v_ac = v - mean(v);

            L = numel(v_ac);
            Fs = 1/dt;
            if L > 1
                P1 = abs(fft(v_ac)/L);
                P1 = P1(1:floor(L/2)+1);
                P1(2:end-1)=2*P1(2:end-1);
                fa = Fs*(0:(L/2))/L;
                P1_smooth = smoothdata(P1, 'movmean', 10);
                [~,im]=max(P1_smooth);
                Fc=fa(im)/1e6;
            else
                Fc=0; P1=[]; fa=[];
            end

            if params.useDynamicS && Fc > 0
                current_S = interp1(curve_F, curve_S, Fc, 'linear', 'extrap');
            else
                current_S = params.S;
            end

            K_MPa = (10^(Att/20) / 10^(G/20)) / current_S;
            K_Pa = K_MPa * 1e6;

            Vpp = max(v_ac)-min(v_ac);
            v_neg = min(v_ac);
            Isptp = max((v_ac * K_Pa).^2 / Zac);
            Pneg  = abs(v_neg) * K_MPa;

            pk = max(abs(v_ac));
            idx_p = find(abs(v_ac)>0.1*pk);
            if ~isempty(idx_p)
                vp = v_ac(idx_p(1):idx_p(end));
                PII = sum((vp*K_Pa).^2 / Zac)*dt;
                Tau = numel(vp)*dt;
                Isppa = PII/Tau;
                Vrms = (sqrt(Isppa*Zac)/1e6)/K_MPa;
                Ispta = PII * PRF;
                t_start = t(idx_p(1));
                t_end   = t(idx_p(end));
                thresh_val = 0.1 * pk;
            else
                PII=0; Tau=0; Isppa=0; Ispta=0; Vrms=0;
                t_start = 0; t_end = 0; thresh_val = 0;
            end

            if L > 1
                if strcmpi(params.maxBy, 'Vpp')
                    crit = Vpp;
                elseif strcmpi(params.maxBy, 'Ppp')
                    crit = Vpp * K_MPa;
                elseif strcmpi(params.maxBy, 'PII')
                    crit = PII;
                elseif strcmpi(params.maxBy, 'Isppa')
                    crit = Isppa;
                elseif strcmpi(params.maxBy, 'Ispta')
                    crit = Ispta;
                else
                    crit = Vpp * K_MPa;
                end

                if crit > max_crit
                    max_crit = crit;
                    bestWave.t = t;
                    bestWave.v = v_ac;
                    bestWave.f = fa/1e6;
                    bestWave.fft = P1;
                    if exist('P1_smooth', 'var') && ~isempty(P1_smooth) && numel(P1_smooth) == numel(P1)
                        bestWave.fft_smooth = P1_smooth;
                    else
                        bestWave.fft_smooth = smoothdata(P1, 'movmean', 10);
                    end
                    bestWave.v_pos = max(v_ac);
                    bestWave.v_neg = v_neg;
                    bestWave.Vpp = Vpp;
                    bestWave.Vrms = Vrms;
                    bestWave.Ppp = Vpp*K_MPa;
                    bestWave.PII = PII;
                    bestWave.Isppa = Isppa;
                    bestWave.Ispta = Ispta;
                    bestWave.Tau = Tau*1e6;
                    bestWave.Fc = Fc;
                    bestWave.t_start = t_start;
                    bestWave.t_end   = t_end;
                    bestWave.thresh  = thresh_val;

                    v_abs = abs(v_ac); v_pk = max(v_abs); t_pk = t(find(v_abs == v_pk, 1));
                    t_dBs = [6, 12, 20, 40]; t_data = zeros(3, 4);
                    for i_tdb = 1:4
                        thresh = v_pk * 10^(-t_dBs(i_tdb)/20); idx_ab = find(v_abs >= thresh);
                        if ~isempty(idx_ab)
                            t_f = t(idx_ab(1)); t_l = t(idx_ab(end));
                            t_data(1, i_tdb) = (t_pk - t_f)*1e6;
                            t_data(2, i_tdb) = (t_l - t_pk)*1e6;
                            t_data(3, i_tdb) = (t_l - t_f)*1e6;
                        end
                    end
                    bestWave.t_data = t_data;

                    P1_bw = bestWave.fft_smooth;
                    P1_pk = max(P1_bw); f_dBs = [3, 6, 12, 20]; f_data = zeros(4, 4);
                    for i_fdb = 1:4
                        thresh = P1_pk * 10^(-f_dBs(i_fdb)/20);
                        idx_ab = find(P1_bw >= thresh);
                        if ~isempty(idx_ab)
                            f_l = fa(idx_ab(1))/1e6; f_u = fa(idx_ab(end))/1e6;
                            f_data(1, i_fdb) = f_l;
                            f_data(2, i_fdb) = (f_l + f_u)/2;
                            f_data(3, i_fdb) = f_u;
                            f_data(4, i_fdb) = f_u - f_l;
                        end
                    end
                    bestWave.f_data = f_data;
                end
            end

            fnames(end+1,1)=string(files(k).name);
            X_l(end+1,1)=X; Y_l(end+1,1)=Y; Z_l(end+1,1)=Z;
            Vpp_l(end+1,1)=Vpp; Vrms_l(end+1,1)=Vrms; Ppp_l(end+1,1)=Vpp*K_MPa; Prms_l(end+1,1)=Vrms*K_MPa;
            PII_l(end+1,1)=PII; Isppa_l(end+1,1)=Isppa; Ispta_l(end+1,1)=Ispta; Isptp_l(end+1,1)=Isptp; Pneg_l(end+1,1)=Pneg;
            Fc_l(end+1,1)=Fc; Tau_l(end+1,1)=Tau*1e6;

        catch ME
            failedFiles(end+1,1) = string(files(k).name);
            failedReasons(end+1,1) = string(ME.message);
            continue;
        end
    end

    if isempty(fnames)
        error('无有效数据');
    end

    if ~isempty(progressCallback)
        progressCallback(100, '处理完成');
    end

    result = table(fnames, X_l, Y_l, Z_l, Fc_l, Vpp_l, Vrms_l, Ppp_l, Prms_l, PII_l, Isppa_l, Ispta_l, Isptp_l, Pneg_l, Tau_l, ...
        'VariableNames',{'File','X','Y','Z','Fc','Vpp','Vrms','Ppp','Prms','PII','Isppa','Ispta','Isptp','Pneg','Tau'});

    if strcmpi(params.maxBy, 'Vpp')
        [~, imax] = max(result.Vpp);
    elseif strcmpi(params.maxBy, 'PII')
        [~, imax] = max(result.PII);
    elseif strcmpi(params.maxBy, 'Isppa')
        [~, imax] = max(result.Isppa);
    elseif strcmpi(params.maxBy, 'Ispta')
        [~, imax] = max(result.Ispta);
    else
        [~, imax] = max(result.Ppp);
    end
    rm = result(imax,:);

    nx = numel(unique(result.X)); ny = numel(unique(result.Y)); nz = numel(unique(result.Z));
    maps = struct();
    maps.is2D = sum([nx>1, ny>1, nz>1]) == 2;
    maps.is3D = sum([nx>1, ny>1, nz>1]) == 3;
    acst = struct();

    if maps.is3D
        maps.Xs = sort(unique(result.X));
        maps.Ys = sort(unique(result.Y));
        maps.Zs = sort(unique(result.Z));
        maps.Mat3D_vpp = nan(ny, nx, nz);
        maps.Mat3D_ppp = nan(ny, nx, nz);
        [~, ia] = ismember(result.X, maps.Xs);
        [~, ib] = ismember(result.Y, maps.Ys);
        [~, ic] = ismember(result.Z, maps.Zs);
        for i = 1:height(result)
            maps.Mat3D_vpp(ib(i), ia(i), ic(i)) = result.Vpp(i);
            maps.Mat3D_ppp(ib(i), ia(i), ic(i)) = result.Ppp(i);
        end
        result_2d = result(result.Z == rm.Z, :);
    else
        result_2d = result;
    end

    if maps.is2D || maps.is3D
        [maps.As, maps.Bs, maps.xl, maps.yl, A, B] = determineScanDimensions(result_2d);
        dx = median(diff(maps.As));
        dy = median(diff(maps.Bs));
        [~, ia] = ismember(A, maps.As);
        [~, ib] = ismember(B, maps.Bs);

        nRows = numel(maps.Bs);
        nCols = numel(maps.As);
        maps.Mat_vpp = nan(nRows, nCols);
        maps.Mat_ppp = nan(nRows, nCols);
        maps.Mat_pta = nan(nRows, nCols);
        maps.Mat_pii = nan(nRows, nCols);
        maps.Mat_ppa = nan(nRows, nCols);
        maps.Mat_ptp = nan(nRows, nCols);

        for i = 1:height(result_2d)
            maps.Mat_vpp(ib(i), ia(i)) = result_2d.Vpp(i);
            maps.Mat_ppp(ib(i), ia(i)) = result_2d.Ppp(i);
            maps.Mat_pta(ib(i), ia(i)) = result_2d.Ispta(i);
            maps.Mat_pii(ib(i), ia(i)) = result_2d.PII(i);
            maps.Mat_ppa(ib(i), ia(i)) = result_2d.Isppa(i);
            maps.Mat_ptp(ib(i), ia(i)) = result_2d.Isptp(i);
        end

        idx = find(result_2d.File == rm.File, 1);
        [maps.bestR, maps.bestC] = findMaxPointIndices(A(idx), B(idx), maps.As, maps.Bs);
        acst.focal_A = maps.As(maps.bestC);
        acst.focal_B = maps.Bs(maps.bestR);
        acst = calculateAcousticParams(acst, maps, rm, params, dx, dy);
    end

    lines = strings(0,1);
    lines(end+1) = "========= 分析报告 =========";
    lines(end+1) = sprintf("最大点位置 (XYZ): (%.1f, %.1f, %.1f)", rm.X, rm.Y, rm.Z);
    lines(end+1) = sprintf("判定基准   : %s 最大", upper(params.maxBy));
    lines(end+1) = sprintf("数据维度   : %dD", maps.is3D*3 + (~maps.is3D)*maps.is2D*2 + (~maps.is3D&&~maps.is2D)*1);
    lines(end+1) = sprintf("PRF 来源   : %s（仅手动输入）", prf_source);
    if ~isnan(global_PRF)
        lines(end+1) = sprintf("PRF 数值   : %.4f Hz", global_PRF);
    else
        lines(end+1) = "PRF 数值   : 无效（应已被前置拦截）";
    end
    lines(end+1) = sprintf("成功文件数 : %d", numel(fnames));
    lines(end+1) = sprintf("失败文件数 : %d", numel(failedFiles));
    lines(end+1) = sprintf("Vpp : %.4f V   | Ppp : %.4f MPa", rm.Vpp, rm.Ppp);
    lines(end+1) = sprintf("Fc  : %.2f MHz | Tau : %.2f us", rm.Fc, rm.Tau);
    if maps.is2D || maps.is3D
        lines(end+1) = "------------------------------";
        lines(end+1) = sprintf("总声功率 W : %.2f mW", acst.Power_mW);
        lines(end+1) = sprintf("Max MI     : %.3f", acst.MI);
        lines(end+1) = sprintf("Max MI,3   : %.3f", acst.MI_3);
    end
    if ~isempty(failedFiles)
        lines(end+1) = "------------------------------";
        lines(end+1) = "失败文件列表:";
        for i_fail = 1:numel(failedFiles)
            lines(end+1) = sprintf("- %s | %s", failedFiles(i_fail), failedReasons(i_fail));
        end
    end
    repStr = lines;
end

function info = analyzeAlignFolder(dataFolder, params, scanAxis)
    [result, ~, ~, ~, ~, ~] = analyzeEngine(dataFolder, params, [], []);

    if isempty(result) || height(result) < 2
        error('文件夹 "%s" 中有效数据不足，无法进行声轴对齐计算。', dataFolder);
    end

    result = sortrows(result, {'Y','X','Z'});
    ySpread = max(result.Y) - min(result.Y);
    if ySpread > 1e-6
        warning('文件夹 "%s" 内部 Y 坐标并不完全恒定，程序将仍按峰值点的 Y 来计算。', dataFolder);
    end

    switch upper(scanAxis)
        case 'X'
            nx = numel(unique(result.X));
            if nx < 2
                error('文件夹 "%s" 不像 X 扫描：X 坐标变化点数不足。', dataFolder);
            end
            result = sortrows(result, 'X');
            axisVals = result.X;
            axisMetric = result.Vpp;
            [peakVpp, idx] = max(axisMetric);

            info.scanAxis   = 'X';
            info.result     = result;
            info.axisVals   = axisVals;
            info.axisMetric = axisMetric;
            info.peakIndex  = idx;
            info.peakVpp    = peakVpp;
            info.peakX      = result.X(idx);
            info.peakY      = result.Y(idx);
            info.peakZ      = result.Z(idx);

        case 'Z'
            nz = numel(unique(result.Z));
            if nz < 2
                error('文件夹 "%s" 不像 Z 扫描：Z 坐标变化点数不足。', dataFolder);
            end
            result = sortrows(result, 'Z');
            axisVals = result.Z;
            axisMetric = result.Vpp;
            [peakVpp, idx] = max(axisMetric);

            info.scanAxis   = 'Z';
            info.result     = result;
            info.axisVals   = axisVals;
            info.axisMetric = axisMetric;
            info.peakIndex  = idx;
            info.peakVpp    = peakVpp;
            info.peakX      = result.X(idx);
            info.peakY      = result.Y(idx);
            info.peakZ      = result.Z(idx);

        otherwise
            error('scanAxis 必须为 X 或 Z');
    end
end

function out = calcTiltFromTwoLines(lineNear, lineFar, mode)
    switch upper(mode)
        case 'X'
            coord1 = lineNear.peakX;
            coord2 = lineFar.peakX;
        case 'Z'
            coord1 = lineNear.peakZ;
            coord2 = lineFar.peakZ;
        otherwise
            error('mode 必须为 X 或 Z');
    end

    y1 = lineNear.peakY;
    y2 = lineFar.peakY;
    dCoord = coord2 - coord1;
    dY = y2 - y1;

    if abs(dY) < 1e-12
        error('两个扫描文件夹的峰值点 Y 坐标相同，无法计算偏转角。');
    end

    out.coord1 = coord1;
    out.coord2 = coord2;
    out.y1 = y1;
    out.y2 = y2;
    out.dCoord = dCoord;
    out.dY = dY;
    out.theta_rad = atan2(dCoord, dY);
    out.theta_deg = out.theta_rad * 180 / pi;
end

function [X,Y,Z,P]=getMeta(m)
    X=NaN; Y=NaN; Z=NaN; P=NaN;
    if width(m)<2, return; end
    s=string(m{:,1}); v=m{:,2};
    i=find(contains(s,"X位"),1); if ~isempty(i), X=v(i); end
    i=find(contains(s,"Y位"),1); if ~isempty(i), Y=v(i); end
    i=find(contains(s,"Z位"),1); if ~isempty(i), Z=v(i); end
    i=find(contains(s,"频率")|contains(s,"Frequency"),1);
    if ~isempty(i)
        P=v(i);
    else
        i=find(contains(s,"周期"),1);
        if ~isempty(i), P=1/v(i); end
    end
end

function [X,Y,Z]=getXYZName(f)
    X=NaN; Y=NaN; Z=NaN;
    t=regexp(f,'X=([-+]?\d+\.?\d*)','tokens','once');
    if ~isempty(t), X=str2double(t); end
    t=regexp(f,'Y=([-+]?\d+\.?\d*)','tokens','once');
    if ~isempty(t), Y=str2double(t); end
    t=regexp(f,'Z=([-+]?\d+\.?\d*)','tokens','once');
    if ~isempty(t), Z=str2double(t); end
end

function [As, Bs, xl, yl, A, B] = determineScanDimensions(result_2d)
    nx2 = numel(unique(result_2d.X));
    ny2 = numel(unique(result_2d.Y));
    nz2 = numel(unique(result_2d.Z));

    if nx2 > 1 && ny2 > 1
        xl = 'X'; yl = 'Y'; A = result_2d.X; B = result_2d.Y;
    elseif nx2 > 1 && nz2 > 1
        xl = 'X'; yl = 'Z'; A = result_2d.X; B = result_2d.Z;
    else
        xl = 'Y'; yl = 'Z'; A = result_2d.Y; B = result_2d.Z;
    end

    As = sort(unique(A));
    Bs = sort(unique(B));
end

function [bestR, bestC] = findMaxPointIndices(A_val, B_val, As, Bs)
    [~, bestC] = ismember(A_val, As);
    [~, bestR] = ismember(B_val, Bs);
    if isempty(bestC) || bestC == 0, bestC = 1; end
    if isempty(bestR) || bestR == 0, bestR = 1; end
end

function acst = calculateAcousticParams(acst, maps, rm, params, dx, dy)
    pii_max = max(maps.Mat_pii(:), [], 'omitnan');
    acst.area_6  = sum(maps.Mat_pii(:) >= pii_max * 10^(-6/10)) * dx * dy;
    acst.area_12 = sum(maps.Mat_pii(:) >= pii_max * 10^(-12/10)) * dx * dy;
    acst.area_20 = sum(maps.Mat_pii(:) >= pii_max * 10^(-20/10)) * dx * dy;

    mask_6dB = (maps.Mat_pii >= pii_max * 10^(-6/10));
    acst.Isata = mean(maps.Mat_pta(mask_6dB), 'omitnan') / 10;
    acst.Isapa = mean(maps.Mat_ppa(mask_6dB), 'omitnan') / 10;
    acst.Isatp = mean(maps.Mat_ptp(mask_6dB), 'omitnan') / 10;

    acst.Ispta = rm.Ispta / 10;
    acst.Isppa = rm.Isppa / 10;
    acst.Isptp = rm.Isptp / 10;

    mask_power = maps.Mat_pii >= pii_max * 10^(-20/10);
    W = sum(maps.Mat_pta(mask_power), 'omitnan') * (dx * dy * 1e-6);
    acst.Power_mW = W * 1000;

    z_cm = rm.Z / 10;
    if isnan(z_cm) || z_cm < 0, z_cm = 0; end
    derate_dB = 0.3 * rm.Fc * z_cm;
    I_derate = 10^(-derate_dB / 10);
    P_derate = 10^(-derate_dB / 20);

    acst.Isptp_3 = acst.Isptp * I_derate;
    acst.Ispta_3 = acst.Ispta * I_derate;
    acst.Isppa_3 = acst.Isppa * I_derate;

    if isfinite(rm.Fc) && rm.Fc > 0
        acst.MI = rm.Pneg / sqrt(rm.Fc);
        acst.MI_3 = (rm.Pneg * P_derate) / sqrt(rm.Fc);
    else
        acst.MI = NaN;
        acst.MI_3 = NaN;
    end
end
