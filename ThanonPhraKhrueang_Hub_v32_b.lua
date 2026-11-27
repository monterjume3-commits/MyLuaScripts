if getgenv().TwoK and getgenv().TwoK.Stop then pcall(getgenv().TwoK.Stop) end
do
	local roots = { (gethui and gethui()) or game:GetService("CoreGui") }
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if pg then roots[#roots + 1] = pg end
	for _, r in ipairs(roots) do
		for _, g in ipairs(r:GetChildren()) do
			pcall(function()
				if g:IsA("ScreenGui") and string.sub(g.Name, 1, 8) == "TwoK_Amu" then g:Destroy() end
			end)
		end
	end
end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local VU      = game:GetService("VirtualUser")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer

local SR   = RS:FindFirstChild("ShopRemotes")
local Act  = SR and SR:FindFirstChild("Act")
local Look = SR and SR:FindFirstChild("Look")
local Push = SR and SR:FindFirstChild("Push")

local SC, Models = {}, {}
do
	local m = RS:FindFirstChild("ShopConfig")
	if m then local ok, r = pcall(require, m) if ok and type(r) == "table" then SC = r end end
	local m2 = RS:FindFirstChild("AmuletLab")
	if m2 then local ok, r = pcall(require, m2)
		if ok and type(r) == "table" and type(r.Models) == "table" then Models = r.Models end end
end

local MIN_LOOK   = 3.0
local COMMISSION = tonumber(SC.Commission) or 0.1

local COND = {}
do
	if type(SC.Condition) == "table" then
		for _, t in ipairs(SC.Condition) do
			if type(t) == "table" then COND[#COND + 1] = { min = tonumber(t[1]) or 0, mult = tonumber(t[2]) or 1 } end
		end
	end
	if #COND == 0 then
		COND = { { min = 95, mult = 1.5 }, { min = 80, mult = 1.2 }, { min = 60, mult = 1.0 }, { min = 30, mult = 0.7 }, { min = 0, mult = 0.4 } }
	end
	table.sort(COND, function(a, b) return a.min > b.min end)
end
local GLETTER = { "A", "A-", "B", "C", "D" }
local function condGrade(c)
	if type(c) ~= "number" then return nil, nil end
	for i, b in ipairs(COND) do if c >= b.min then return i, b.mult end end
	return #COND, 0.4
end
local function money(n)
	if type(n) ~= "number" or n ~= n then return "-" end
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n))):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (neg and "-" or "") .. (s:gsub("^,", ""))
end
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
	if parent then o.Parent = parent end
	return o
end

local TIER_RANK = { common = 1, good = 2, rare = 3, vrare = 4, legend = 5, ancient = 6 }
local TIER_LIST, TIER_NAME, TIER_COUNT = {}, {}, {}
do
	local seen = {}
	for _, md in pairs(Models) do
		if type(md) == "table" then
			local t = tostring(md.Tier or "?")
			TIER_COUNT[t] = (TIER_COUNT[t] or 0) + 1
			if not seen[t] then
				seen[t] = true
				TIER_LIST[#TIER_LIST + 1] = { tier = t, thai = tostring(md.TierName or t) }
				TIER_NAME[t] = tostring(md.TierName or t)
			end
		end
	end
	table.sort(TIER_LIST, function(a, b) return (TIER_RANK[a.tier] or 99) < (TIER_RANK[b.tier] or 99) end)
end
local TIER_COL = {
	common = Color3.fromRGB(190,200,215), good = Color3.fromRGB(130,215,155),
	rare = Color3.fromRGB(120,185,255),  vrare = Color3.fromRGB(190,150,255),
	legend = Color3.fromRGB(255,180,90),  ancient = Color3.fromRGB(255,226,120),
}

local COL_TXT    = Color3.fromRGB(236,242,252)
local COL_DIM    = Color3.fromRGB(170,182,202)
local COL_BG     = Color3.fromRGB(14,16,24)
local COL_PANEL  = Color3.fromRGB(28,33,46)
local COL_BTN    = Color3.fromRGB(48,56,76)
local COL_OK     = Color3.fromRGB(44,82,60)
local COL_BAD    = Color3.fromRGB(84,46,54)
local COL_BLUE   = Color3.fromRGB(52,72,104)
local COL_GREEN  = Color3.fromRGB(126,222,152)
local COL_RED    = Color3.fromRGB(255,130,130)
local COL_YEL    = Color3.fromRGB(240,210,120)
local COL_STROKE = Color3.fromRGB(90,104,138)

local Hub = {
	Running = true, State = nil, StateAt = 0, CustId = nil, Demo = false,
	Flags = {
		Farm = false, OnlyGenuine = true, AllowUnknown = false, AllowFake = false,
		MinCond = 60, MinValue = 0, MinProfit = 0,
		AutoHandBack = true, AutoPost = false, AntiAfk = true, RequireLook = true,
	},
	LookedAt = {}, LastAct = {}, Fail = {}, Done = {}, Logs = {}, Conns = {}, TierOn = {},
}
for _, t in ipairs(TIER_LIST) do Hub.TierOn[t.tier] = true end
getgenv().TwoK = Hub

local function log(msg)
	Hub.Logs[#Hub.Logs + 1] = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg))
	if #Hub.Logs > 60 then table.remove(Hub.Logs, 1) end
end
local function keyOf(i) return tostring(Hub.CustId) .. ":" .. tostring(i) end

local function syncCust(Cu)
	if type(Cu) ~= "table" or Cu.Id == nil then return end
	local cid = tostring(Cu.Id)
	if Hub.CustId ~= cid then
		Hub.CustId = cid; Hub.LookedAt = {}; Hub.LastAct = {}
		Hub.Fail = {}; Hub.Done = {}
		log("ลูกค้าใหม่ #" .. cid)
	end
end

local function itemsOf(Cu)
	if type(Cu) ~= "table" then return {} end
	if type(Cu.Items) == "table" and #Cu.Items > 0 then return Cu.Items end
	if type(Cu.Spec) == "table" then return { { Spec = Cu.Spec, Stage = Cu.Stage, Ask = Cu.Ask } } end
	return {}
end
local function specOf(it) return type(it.Spec) == "table" and it.Spec or it end

local function analyze(it, i)
	local sp    = specOf(it)
	local id    = sp.Model or it.Model
	local md    = Models[id]
	local feats = (type(sp.Features) == "table" and sp.Features) or {}
	local o = { i = i, stage = tostring(it.Stage or sp.Stage or "?"), id = id,
	            why = {}, verdict = "unknown", demo = it.demo }
	o.name     = (md and md.Name) or tostring(id or "?")
	o.tier     = (md and md.Tier) or "?"
	o.tierName = (md and md.TierName) or "?"
	o.cond     = tonumber(sp.Condition)

	local mesh = md and md.Mesh
	if feats.Proc ~= nil then
		o.verdict = "fake"
		o.why[#o.why + 1] = "เนื้อปลอม Proc=" .. tostring(feats.Proc)
	end
	if mesh and feats.Variant ~= nil and tostring(feats.Variant) ~= tostring(mesh) then
		o.verdict = "fake"
		o.why[#o.why + 1] = "ลายไม่ตรง (" .. tostring(feats.Variant) .. ")"
	end
	if o.verdict ~= "fake" and mesh and feats.Variant ~= nil and tostring(feats.Variant) == tostring(mesh) then
		o.verdict = "genuine"
	end
	if o.verdict == "unknown" then
		local ck = md and md.Checks
		if type(ck) ~= "table" or #ck == 0 then o.why[#o.why + 1] = "พิมพ์นี้ตรวจไม่ได้"
		else o.why[#o.why + 1] = "ข้อมูลลายไม่พอ" end
	end

	local gi, mult = condGrade(o.cond)
	o.grade  = gi and GLETTER[gi] or "-"
	o.mult   = mult
	o.value  = (tonumber(md and md.Price) or 0) * (mult or 1)
	o.ask    = tonumber(it.Ask or it.PostAsk or it.Fee or sp.Ask) or 0
	o.profit = o.value * (1 - COMMISSION) - o.ask
	return o
end

local function passFilter(a)
	local F = Hub.Flags
	if a.verdict == "fake" and not F.AllowFake then return false, "เก๊" end
	if a.verdict == "unknown" and not F.AllowUnknown then return false, "ตรวจไม่ได้" end
	local allowed = (a.verdict == "fake" and F.AllowFake) or (a.verdict == "unknown" and F.AllowUnknown)
	if F.OnlyGenuine and a.verdict ~= "genuine" and not allowed then return false, "ไม่ใช่แท้" end
	if a.cond and a.cond < (F.MinCond or 0) then return false, "สภาพต่ำ" end
	if a.value < (F.MinValue or 0) then return false, "มูลค่าต่ำ" end
	if a.profit < (F.MinProfit or 0) then return false, "กำไรต่ำ" end
	if Hub.TierOn[a.tier] == false then return false, "ระดับถูกปิด" end
	return true, "ok"
end

local function doLook(i)
	Hub.LookedAt[keyOf(i)] = os.clock()
	if Look then pcall(function() Look:FireServer(i) end) log("ส่อง #" .. tostring(i)) end
end

local function doAct(kind, i)
	if not Act then return end
	local k = keyOf(i)
	local looked = Hub.LookedAt[k]
	local dt = looked and (os.clock() - looked) or 4.0
	local ok, res = pcall(function() return Act:InvokeServer(kind, { i = i, dt = dt }) end)
	local good = ok and res ~= false and res ~= nil
	if good then
		Hub.Fail[k] = nil
		Hub.LastAct[k] = os.clock()
	else
		local n = (Hub.Fail[k] or 0) + 1
		Hub.Fail[k] = n
		Hub.LastAct[k] = os.clock() + math.min(15, 1.5 * n)
		if n >= 3 then
			Hub.Done[k] = true
			log(string.format("%s #%s ถูกปฏิเสธ %d ครั้ง → ข้ามไอเทมนี้", kind, tostring(i), n))
		end
	end
	log(string.format("%s #%s → %s (dt %.1f)", kind, tostring(i), tostring(res), dt))
end

if Push then
	Hub.Conns[#Hub.Conns + 1] = Push.OnClientEvent:Connect(function(a, b)
		local st
		if type(a) == "table" then st = a
		elseif a == "state" and type(b) == "table" then st = b end
		if st then
			Hub.State, Hub.StateAt = st, os.clock()
		end
	end)
end

task.spawn(function()
	while Hub.Running do
		local ok, err = pcall(function()
			local S = Hub.State
			if not S or not Hub.Flags.Farm then return end
			local Cu = S.Customer
			if type(Cu) ~= "table" then return end
			local F = Hub.Flags
			syncCust(Cu)
			for i, it in ipairs(itemsOf(Cu)) do
				local st = tostring(it.Stage or "?")
				local k  = keyOf(i)
				if Hub.Done[k] then
				elseif st == "offer" then
					if F.RequireLook and not Hub.LookedAt[k] then
						doLook(i)
					else
						local lk = Hub.LookedAt[k]
						local ready = (not F.RequireLook) or (lk and (os.clock() - lk) >= MIN_LOOK + 0.15)
						if ready and os.clock() - (Hub.LastAct[k] or 0) > 1.5 then
							local okf, why = passFilter(analyze(it, i))
							if okf then doAct("buy", i)
							else doAct("pass", i); log("ปฏิเสธ #" .. i .. " (" .. why .. ")") end
						end
					end
				elseif st == "return" then
					if F.AutoHandBack and os.clock() - (Hub.LastAct[k] or 0) > 2 then
						doAct("handBack", i)
					end
				elseif st == "post" then
					if F.AutoPost and os.clock() - (Hub.LastAct[k] or 0) > 2 then
						doAct(passFilter(analyze(it, i)) and "buyPost" or "pass", i)
					end
				end
			end
		end)
		if not ok then log("worker: " .. tostring(err)) end
		task.wait(0.25)
	end
end)

if LP then
	Hub.Conns[#Hub.Conns + 1] = LP.Idled:Connect(function()
		if Hub.Flags.AntiAfk then pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end) end
	end)
end

-- ══════════════════════════════ UI ══════════════════════════════════════════
local fadeList = {}
local function fade(inst, base) fadeList[#fadeList + 1] = { inst = inst, base = base or 0 } end

local gui = new("ScreenGui", {
	Name = "TwoK_Amulet_v56", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, (gethui and gethui()) or game:GetService("CoreGui"))

local win = new("Frame", {
	Name = "Win", BackgroundColor3 = COL_BG, BackgroundTransparency = 0.08,
	BorderSizePixel = 0, ClipsDescendants = true,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, win)
new("UIStroke", { Color = COL_STROKE, Transparency = 0.45, Thickness = 1.4 }, win)
fade(win, 0.08)

local function fitWin()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local w = math.min(700, vp.X - 24)
	local h = math.min(340, vp.Y - 70)
	win.Size = UDim2.fromOffset(w, h)
	win.Position = UDim2.fromOffset(12, math.max(6, vp.Y - h - 100))
end
fitWin()

local head = new("Frame", {
	Name = "Head", Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = COL_PANEL,
	BackgroundTransparency = 0.12, BorderSizePixel = 0,
}, win)
fade(head, 0.12)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, head)
new("TextLabel", {
	Size = UDim2.new(0, 150, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
	Text = "ถนนพระเครื่อง — Hub v32", Font = Enum.Font.GothamBold, TextSize = 15,
	TextColor3 = COL_TXT, TextXAlignment = Enum.TextXAlignment.Left,
}, head)

local hb = new("Frame", {
	Size = UDim2.new(0, 300, 1, 0), Position = UDim2.new(1, -306, 0, 0), BackgroundTransparency = 1,
}, head)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center,
}, hb)

local function mkBtn(par, text, w, col, cb, sz)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(w or 58, sz or 24), BackgroundColor3 = col or COL_BTN,
		BackgroundTransparency = 0.1, BorderSizePixel = 0,
		Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = COL_TXT,
	}, par)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	fade(b, 0.1)
	if cb then b.MouseButton1Click:Connect(cb) end
	return b
end

local body, toggleBtn
local collapsed, expandH = false, win.Size.Y.Offset
local lastSig = ""
local function setCollapsed(v)
	collapsed = v
	if v then
		expandH = win.Size.Y.Offset
		win.Size = UDim2.fromOffset(win.Size.X.Offset, 34)
	else
		win.Size = UDim2.fromOffset(win.Size.X.Offset, math.max(200, expandH))
	end
	if body then body.Visible = not v end
	if toggleBtn then toggleBtn.Text = v and "▢" or "▁" end
end

local manualRefresh

local farmBtn
farmBtn = mkBtn(hb, "ฟาร์ม: ปิด", 92, COL_BTN, function()
	Hub.Flags.Farm = not Hub.Flags.Farm
	farmBtn.Text = "ฟาร์ม: " .. (Hub.Flags.Farm and "เปิด" or "ปิด")
	farmBtn.BackgroundColor3 = Hub.Flags.Farm and COL_OK or COL_BTN
	log("ออโต้ฟาร์ม " .. tostring(Hub.Flags.Farm))
end)

-- v56: ปุ่มขายพระเก๊ใน Safe (Act "sellFakes")
mkBtn(hb, "ขายเก๊", 66, COL_BAD, function()
	if not Act then log("ไม่พบ ShopRemotes.Act") return end
	local ok, res = pcall(function() return Act:InvokeServer("sellFakes") end)
	log("sellFakes → " .. (ok and tostring(res) or ("error: " .. tostring(res))))
end)

toggleBtn = mkBtn(hb, "▁", 34, COL_BTN, function() setCollapsed(not collapsed) end)
mkBtn(hb, "⟳", 34, COL_BLUE, function() if manualRefresh then manualRefresh() end end)
mkBtn(hb, "✕", 34, COL_BAD, function() pcall(function() Hub.Stop() end) end)

do
	local drag, sp, si = false, nil, nil
	head.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			drag = true; sp = win.Position; si = Vector2.new(i.Position.X, i.Position.Y)
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputChanged:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(i.Position.X, i.Position.Y) - si
			win.Position = UDim2.fromOffset(sp.X.Offset + d.X, sp.Y.Offset + d.Y)
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
	end)
end

body = new("Frame", {
	Name = "Body", Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34),
	BackgroundTransparency = 1,
}, win)

local grip = new("TextButton", {
	Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -20, 1, -20),
	BackgroundTransparency = 1, Text = "◢", TextSize = 12,
	Font = Enum.Font.GothamBold, TextColor3 = COL_DIM,
}, win)
do
	local gd, g0, gs = false, nil, nil
	grip.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			gd = true
			g0 = Vector2.new(win.Size.X.Offset, win.Size.Y.Offset)
			gs = Vector2.new(i.Position.X, i.Position.Y)
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputChanged:Connect(function(i)
		if gd and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(i.Position.X, i.Position.Y) - gs
			win.Size = UDim2.fromOffset(math.clamp(g0.X + d.X, 400, 1300), math.clamp(g0.Y + d.Y, 190, 900))
			if not collapsed then expandH = win.Size.Y.Offset end
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then gd = false end
	end)
end

do
	local cam = workspace.CurrentCamera
	if cam then
		Hub.Conns[#Hub.Conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() fitWin() end)
	end
end

local tabBar = new("Frame", { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 4), BackgroundTransparency = 1 }, body)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabBar)
local pages, tabs = {}, {}
for n, nm in ipairs({ "ลูกค้า", "กรอง", "ดีไซน์" }) do
	tabs[n] = mkBtn(tabBar, nm, 80, COL_BTN, nil, 24)
	pages[n] = new("Frame", { Size = UDim2.new(1, -12, 1, -64), Position = UDim2.fromOffset(6, 34),
		BackgroundTransparency = 1, Visible = false }, body)
end
local function showTab(n)
	for i, p in pairs(pages) do p.Visible = (i == n) end
	for i, b in pairs(tabs) do b.BackgroundColor3 = (i == n) and COL_BLUE or COL_BTN end
end
for n, b in ipairs(tabs) do b.MouseButton1Click:Connect(function() showTab(n) end) end

-- ══════════ หน้า 1 ═══════════
local split = new("Frame", { Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1 }, pages[1])
local leftPane = new("Frame", { BackgroundTransparency = 1 }, split)
local rightPane = new("Frame", {
	BackgroundColor3 = COL_PANEL, BackgroundTransparency = 0.35, BorderSizePixel = 0,
}, split)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, rightPane)
fade(rightPane, 0.35)

local function layoutSplit()
	local w = split.AbsoluteSize.X
	if w <= 0 then w = math.max(200, win.Size.X.Offset - 20) end
	if w < 560 then
		leftPane.Size = UDim2.new(1, 0, 0.58, -2)
		leftPane.Position = UDim2.fromOffset(0, 0)
		rightPane.Size = UDim2.new(1, 0, 0.42, -2)
		rightPane.Position = UDim2.new(0, 0, 0.58, 2)
	else
		leftPane.Size = UDim2.new(0.58, -3, 1, 0)
		leftPane.Position = UDim2.fromOffset(0, 0)
		rightPane.Size = UDim2.new(0.42, -3, 1, 0)
		rightPane.Position = UDim2.new(0.58, 3, 0, 0)
	end
end
layoutSplit()

local cards = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, leftPane)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, cards)
local emptyLbl = new("TextLabel", {
	Size = UDim2.new(1, -8, 0, 70), BackgroundTransparency = 1,
	Text = "รอลูกค้า... (ไปยืนหน้าเคาน์เตอร์)", Font = Enum.Font.Gotham, TextSize = 14,
	TextColor3 = COL_DIM, TextWrapped = true, LayoutOrder = 0,
}, cards)

local logHead = new("Frame", {
	Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 2), BackgroundTransparency = 1,
}, rightPane)
new("TextLabel", {
	Size = UDim2.new(1, -70, 1, 0), BackgroundTransparency = 1,
	Text = "บันทึกผลการกระทำ", Font = Enum.Font.GothamBold, TextSize = 12,
	TextColor3 = COL_DIM, TextXAlignment = Enum.TextXAlignment.Left,
}, logHead)
local refreshBtn = mkBtn(logHead, "รีเฟรช", 62, COL_BLUE, nil, 20)
refreshBtn.Position = UDim2.new(1, -62, 0, 1)

local logScroll = new("ScrollingFrame", {
	Size = UDim2.new(1, -8, 1, -28), Position = UDim2.fromOffset(4, 26),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, rightPane)
local logLbl = new("TextLabel", {
	Size = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.Code,
	TextSize = 11, TextColor3 = COL_DIM, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	AutomaticSize = Enum.AutomaticSize.Y, Text = "",
}, logScroll)

local function mkCard(order, it, a)
	local vt, vc, vb = "ตรวจไม่ได้", COL_YEL, COL_BAD
	if a.verdict == "genuine" then vt, vc, vb = "แท้", COL_GREEN, COL_OK
	elseif a.verdict == "fake" then vt, vc, vb = "เก๊", COL_RED, COL_BAD end

	local card = new("Frame", {
		Size = UDim2.new(1, -8, 0, 78), BackgroundColor3 = COL_PANEL, BackgroundTransparency = 0.18,
		BorderSizePixel = 0, LayoutOrder = order,
	}, cards)
	fade(card, 0.18)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
	new("UIStroke", { Color = vb, Transparency = 0.15, Thickness = 1.2 }, card)

	new("TextLabel", {
		Size = UDim2.new(1, -186, 0, 18), Position = UDim2.fromOffset(8, 3), BackgroundTransparency = 1,
		Text = string.format("#%d %s (%s)", a.i, a.name, a.tierName),
		Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = TIER_COL[a.tier] or COL_TXT,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)
	new("TextLabel", {
		Size = UDim2.new(1, -186, 0, 16), Position = UDim2.fromOffset(8, 21), BackgroundTransparency = 1,
		Text = string.format("สภาพ %s/100 · %s · ×%.2f · มูลค่า %s · กำไร %s",
			a.cond and string.format("%d", math.floor(a.cond)) or "-",
			a.grade, a.mult or 1, money(a.value), money(a.profit)),
		Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = COL_TXT,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)
	new("TextLabel", {
		Size = UDim2.new(1, -186, 0, 16), Position = UDim2.fromOffset(8, 39), BackgroundTransparency = 1,
		Text = "ขาย " .. money(a.ask) .. " · " .. a.stage .. (a.why[1] and (" · " .. table.concat(a.why, " · ")) or ""),
		Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = (a.verdict == "fake") and COL_RED or COL_DIM,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)

	local badge = new("TextLabel", {
		Size = UDim2.fromOffset(64, 20), Position = UDim2.new(1, -72, 0, 4),
		BackgroundColor3 = vb, BackgroundTransparency = 0.12, BorderSizePixel = 0,
		Text = vt, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = vc,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, badge)

	if a.demo then
		new("TextLabel", {
			Size = UDim2.new(0, 160, 0, 22), Position = UDim2.new(1, -168, 0, 46),
			BackgroundTransparency = 1, Text = "ตัวอย่าง (ไม่ใช่ของจริง)",
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = COL_DIM,
		}, card)
	else
		local row = new("Frame", {
			Size = UDim2.new(0, 164, 0, 24), Position = UDim2.new(1, -172, 0, 48),
			BackgroundTransparency = 1,
		}, card)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, row)
		local idx = a.i
		mkBtn(row, "ส่อง", 34, COL_BTN, function() syncCust(Hub.State and Hub.State.Customer); doLook(idx) end, 24)
		mkBtn(row, "ซื้อ", 34, COL_OK, function() syncCust(Hub.State and Hub.State.Customer); doAct("buy", idx) end, 24)
		mkBtn(row, "ปฏิเสธ", 46, COL_BAD, function() syncCust(Hub.State and Hub.State.Customer); doAct("pass", idx) end, 24)
		mkBtn(row, "คืน", 34, COL_BLUE, function() syncCust(Hub.State and Hub.State.Customer); doAct("handBack", idx) end, 24)
	end
	return card
end

-- ── หน้า 2: กรอง ───────────────────────────────────────────────────────────
local p2 = pages[2]
local tierBox = new("Frame", { Size = UDim2.new(1, -4, 0, 30), BackgroundTransparency = 1 }, p2)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, tierBox)
for _, tl in ipairs(TIER_LIST) do
	local t = tl.tier
	local c = new("TextButton", {
		Size = UDim2.fromOffset(104, 26), BackgroundColor3 = COL_BTN, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = COL_DIM,
	}, tierBox)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, c)
	fade(c, 0.05)
	local function paint()
		local on = Hub.TierOn[t] ~= false
		c.Text = (on and "✓ " or "✕ ") .. (TIER_NAME[t] or t) .. " " .. tostring(TIER_COUNT[t] or 0)
		c.BackgroundColor3 = on and (TIER_COL[t] or COL_OK) or COL_BTN
		c.TextColor3 = on and Color3.fromRGB(20, 22, 30) or COL_DIM
	end
	c.MouseButton1Click:Connect(function()
		Hub.TierOn[t] = not (Hub.TierOn[t] ~= false)
		paint(); lastSig = "!"
	end)
	paint()
end

local fgrid = new("ScrollingFrame", {
	Size = UDim2.new(1, -4, 1, -36), Position = UDim2.fromOffset(0, 34),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, p2)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(216, 44), CellPadding = UDim2.fromOffset(6, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, fgrid)

local function mkToggle(par, text, key, order)
	local b = new("TextButton", {
		Size = UDim2.new(0, 210, 0, 28), BackgroundColor3 = COL_BTN, BackgroundTransparency = 0.1,
		BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = COL_TXT,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order or 0,
	}, par)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	fade(b, 0.1)
	local function paint()
		local on = Hub.Flags[key]
		b.Text = (on and "  ✓ " or "  ✕ ") .. text
		b.BackgroundColor3 = on and COL_OK or COL_BTN
	end
	b.MouseButton1Click:Connect(function() Hub.Flags[key] = not Hub.Flags[key]; paint(); lastSig = "!" end)
	paint()
	return b
end

local function mkSlider(par, label, minv, maxv, step, def, order, fmt, cb)
	local row = new("Frame", { Size = UDim2.new(0, 216, 0, 44), BackgroundTransparency = 1, LayoutOrder = order }, par)
	local lbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = 12, TextColor3 = COL_TXT, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local track = new("Frame", {
		Size = UDim2.new(1, -8, 0, 10), Position = UDim2.fromOffset(0, 22),
		BackgroundColor3 = Color3.fromRGB(60, 68, 90), BackgroundTransparency = 0.15, BorderSizePixel = 0,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	fade(track, 0.15)
	local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL_GREEN, BorderSizePixel = 0 }, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	local function set(v)
		v = math.clamp(v, minv, maxv)
		fill.Size = UDim2.fromScale((v - minv) / math.max(1e-6, maxv - minv), 1)
		lbl.Text = string.format("%s: %s", label, (fmt or tostring)(v))
		if cb then cb(v) end
	end
	local drag = false
	local function fromX(x)
		local ap, as = track.AbsolutePosition.X, math.max(1, track.AbsoluteSize.X)
		local t = math.clamp((x - ap) / as, 0, 1)
		local v = minv + (maxv - minv) * t
		if step and step > 0 then v = math.floor(v / step + 0.5) * step end
		set(v)
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			drag = true; fromX(i.Position.X)
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputChanged:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			fromX(i.Position.X)
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
	end)
	set(def)
	return row
end

mkToggle(fgrid, "ซื้อเฉพาะพระแท้",       "OnlyGenuine",   1)
mkToggle(fgrid, "รับพระตรวจไม่ได้",       "AllowUnknown",  2)
mkToggle(fgrid, "รับพระเก๊ (ไม่แนะนำ)",   "AllowFake",     3)
mkToggle(fgrid, "คืนพระอัตโนมัติ",        "AutoHandBack",  4)
mkToggle(fgrid, "รับ post อัตโนมัติ",     "AutoPost",      5)
mkToggle(fgrid, "ส่องก่อนซื้อ (3 วิ)",    "RequireLook",   6)
mkToggle(fgrid, "กันหลุดอัตโนมัติ",       "AntiAfk",       7)
mkSlider(fgrid, "สภาพขั้นต่ำ", 0, 100, 1, 60, 8, function(v) return string.format("%d", v) end,
	function(v) Hub.Flags.MinCond = v; lastSig = "!" end)
mkSlider(fgrid, "มูลค่าขั้นต่ำ", 0, 300000, 1000, 0, 9, money,
	function(v) Hub.Flags.MinValue = v; lastSig = "!" end)
mkSlider(fgrid, "กำไรขั้นต่ำ", -100000, 300000, 1000, 0, 10, money,
	function(v) Hub.Flags.MinProfit = v; lastSig = "!" end)

-- ── หน้า 3: ดีไซน์ ─────────────────────────────────────────────────────────
local d4 = new("ScrollingFrame", {
	Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
}, pages[3])
new("UIListLayout", { Padding = UDim.new(0, 6) }, d4)
local function applyAlpha(a)
	for _, f in ipairs(fadeList) do
		pcall(function() f.inst.BackgroundTransparency = math.clamp(f.base + a, 0, 0.95) end)
	end
end
mkSlider(d4, "ความโปร่งใส (ตัวหนังสือยังทึบ)", 0, 0.9, 0.01, 0.25, 1,
	function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end, applyAlpha)
local qr = new("Frame", { Size = UDim2.new(1, -8, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, d4)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, qr)
mkBtn(qr, "ทึบ", 62, COL_BTN, function() applyAlpha(0.02) end, 26)
mkBtn(qr, "กึ่ง", 62, COL_BTN, function() applyAlpha(0.45) end, 26)
mkBtn(qr, "ใส",  62, COL_BTN, function() applyAlpha(0.85) end, 26)
mkBtn(qr, "ทดสอบการ์ด", 96, COL_BLUE, function()
	Hub.Demo = not Hub.Demo; lastSig = "!"
	log("ตัวอย่างการ์ด " .. tostring(Hub.Demo))
end, 26)

local status = new("TextLabel", {
	Size = UDim2.new(1, -14, 0, 22), Position = UDim2.new(0, 6, 1, -26), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = COL_DIM,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, body)

local demoIds = {}
for id in pairs(Models) do demoIds[#demoIds + 1] = id end
table.sort(demoIds)
local DEMO1, DEMO2
do
	local id1, id2 = demoIds[1], demoIds[2]
	if id1 and Models[id1] then
		DEMO1 = { demo = true, Stage = "offer", Ask = 1500,
			Spec = { Model = id1, Condition = 97, Features = { Variant = Models[id1].Mesh } } }
	end
	if id2 and Models[id2] then
		DEMO2 = { demo = true, Stage = "offer", Ask = 800,
			Spec = { Model = id2, Condition = 42, Features = { Variant = "R1_F1", Proc = "pores" } } }
	end
end

local lastLogN, lastSplitW = -1, -1
local function render()
	local S  = Hub.State
	local Cu = (type(S) == "table") and S.Customer or nil
	if Cu then syncCust(Cu) end
	local items = itemsOf(Cu)
	local sig = (Hub.Demo and "D" or "") .. tostring(Cu and Cu.Id)
	for i, it in ipairs(items) do
		local sp = specOf(it)
		sig = sig .. string.format("|%d:%s:%s:%s:%s:%s", i, tostring(it.Stage), tostring(sp.Model),
			tostring(sp.Condition), tostring(sp.Features and sp.Features.Variant), tostring(sp.Features and sp.Features.Proc))
	end
	if sig ~= lastSig then
		lastSig = sig
		for _, c in ipairs(cards:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local n = 0
		for i, it in ipairs(items) do n = n + 1; mkCard(n, it, analyze(it, i)) end
		if Hub.Demo then
			if DEMO1 then n = n + 1; mkCard(n, DEMO1, analyze(DEMO1, n)) end
			if DEMO2 then n = n + 1; mkCard(n, DEMO2, analyze(DEMO2, n)) end
		end
		emptyLbl.Visible = (n == 0)
	end
	if status then
		local age = os.clock() - Hub.StateAt
		if type(S) ~= "table" then
			status.Text = "ยังไม่ได้รับข้อมูลจากเกม (รอ Push)"
		elseif type(Cu) == "table" then
			status.Text = string.format("ลูกค้า #%s · %d องค์ · วัน %s · เงิน %s · push %.1fs",
				tostring(Cu.Id), #items, tostring(S.Day or "-"), money(tonumber(S.Cash) or 0), age)
		else
			status.Text = string.format("รอลูกค้า ~%.0fs · วัน %s · เงิน %s · push %.1fs",
				math.max(0, tonumber(S.CustomerGap) or 0), tostring(S.Day or "-"),
				money(tonumber(S.Cash) or 0), age)
		end
	end
	if logLbl and #Hub.Logs ~= lastLogN then
		lastLogN = #Hub.Logs
		logLbl.Text = table.concat(Hub.Logs, "\n")
		task.defer(function()
			pcall(function()
				logScroll.CanvasPosition = Vector2.new(0, math.max(0, logLbl.AbsoluteSize.Y - logScroll.AbsoluteSize.Y))
			end)
		end)
	end
	local w = split.AbsoluteSize.X
	if w ~= lastSplitW then lastSplitW = w; layoutSplit() end
end

manualRefresh = function()
	lastSig = "!"
	lastLogN = -1
	log("รีเฟรชแมนนวล")
	pcall(render)
end
refreshBtn.MouseButton1Click:Connect(manualRefresh)

showTab(1)
applyAlpha(0.25)

function Hub.Stop()
	Hub.Running = false
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	if getgenv().TwoK == Hub then getgenv().TwoK = nil end
end

log("Hub v56 พร้อม · " .. #TIER_LIST .. " ระดับ · Models " .. (function() local n=0 for _ in pairs(Models) do n=n+1 end return n end)())
task.spawn(function()
	while Hub.Running do
		pcall(render)
		task.wait(0.3)
	end
end)
render()
print("v56 loaded")