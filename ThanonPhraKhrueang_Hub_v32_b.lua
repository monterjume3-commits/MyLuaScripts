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
-- ชื่อ action ของปุ่ม "ส่งเครื่อง" ในเกม (ใช้เรียก Act:InvokeServer(kind, ...))
-- ใส่ชื่อจริงตรงนี้ เช่น local SEND_KIND = "xxx"  ถ้ายังเป็น nil จะแค่บันทึกใน log
local SEND_KIND  = nil
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
		ReturnAllFirst = true, SendFallback = true,
	},
	LookedAt = {}, LastAct = {}, Fail = {}, Done = {}, Logs = {}, Conns = {}, TierOn = {},
	Checked = {}, HadReturn = false, SendWarned = false,
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
		Hub.Fail = {}; Hub.Done = {}; Hub.Checked = {}; Hub.HadReturn = false
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
	return good, res
end

-- ข้อ 2.1: พระแท้ที่ซื้อไม่ได้ → ส่งเครื่อง
local function sendMachine(i)
	if not Hub.Flags.SendFallback then return false end
	if not SEND_KIND then
		if not Hub.SendWarned then
			Hub.SendWarned = true
			log("ซื้อไม่ได้ → ต้องส่งเครื่อง แต่ยังไม่ได้ตั้ง SEND_KIND ในสคริปต์")
		end
		return false
	end
	log("ซื้อไม่ได้ #" .. tostring(i) .. " → ส่งเครื่อง")
	return (doAct(SEND_KIND, i))
end

local VERDICT_TH = { genuine = "แท้", fake = "เก๊", unknown = "ตรวจไม่ได้" }

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
			local items = itemsOf(Cu)

			-- ข้อ 4: นับพระที่ยังต้องคืน
			local pendingReturn = 0
			for i, it in ipairs(items) do
				if tostring(it.Stage or "?") == "return" and not Hub.Done[keyOf(i)] then
					pendingReturn = pendingReturn + 1
				end
			end
			if pendingReturn > 0 then Hub.HadReturn = true end
			local holdOffers = F.ReturnAllFirst and F.AutoHandBack and pendingReturn > 0

			for i, it in ipairs(items) do
				local st = tostring(it.Stage or "?")
				local k  = keyOf(i)
				if Hub.Done[k] then
				elseif st == "offer" then
					if holdOffers then
						-- รอคืนพระให้ครบก่อน ค่อยตัดสินใจซื้อ/ปฏิเสธ
					elseif F.RequireLook and not Hub.LookedAt[k] then
						doLook(i)
					else
						local lk = Hub.LookedAt[k]
						local ready = (not F.RequireLook) or (lk and (os.clock() - lk) >= MIN_LOOK + 0.15)
						if ready and os.clock() - (Hub.LastAct[k] or 0) > 1.5 then
							local a = analyze(it, i)
							-- ข้อ 1: ตรวจแท้/เก๊ (บันทึกครั้งเดียวต่อองค์)
							if not Hub.Checked[k] then
								Hub.Checked[k] = true
								log(string.format("ตรวจ #%d %s → %s%s", i, a.name,
									VERDICT_TH[a.verdict] or a.verdict, a.why[1] and (" (" .. a.why[1] .. ")") or ""))
							end
							local okf, why = passFilter(a)
							local tag = Hub.HadReturn and "[หลังคืนครบ] " or ""
							if okf then
								-- ข้อ 2 / 4.1: ผ่านตัวกรอง → ซื้อ
								local cash = tonumber(S.Cash)
								local afford = not (cash and a.ask > cash)
								local good = false
								if afford then
									log(tag .. "ผ่านตัวกรอง → ซื้อ #" .. i)
									good = doAct("buy", i)
								else
									log(string.format("เงินไม่พอ #%d (ขาย %s / มี %s)", i, money(a.ask), money(cash)))
								end
								-- ข้อ 2.1: ซื้อไม่ได้ → ส่งเครื่อง
								if not good then
									local sent = sendMachine(i)
									if not sent then Hub.LastAct[k] = os.clock() + 3 end
								end
							else
								-- ข้อ 3 / 4.2: เก๊ หรือไม่ผ่านตัวกรอง → ปฏิเสธ
								doAct("pass", i)
								log(tag .. "ปฏิเสธ #" .. i .. " (" .. why .. ")")
							end
						end
					end
				elseif st == "return" then
					-- ข้อ 4: คืนพระทั้งหมด
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
	Text = "ถนนพระเครื่อง — Hub v33", Font = Enum.Font.GothamBold, TextSize = 15,
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
	ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize =
