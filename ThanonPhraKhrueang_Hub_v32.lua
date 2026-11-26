-- ============================================================================
--  ถนนพระเครื่อง — Hub v32
--
--  ต้นเหตุจริง (วัดสดในเซิร์ฟเวอร์นี้):
--    ReplicatedStorage.AmuletLab.Models[id].Tier เป็น "สตริง" ไม่ใช่ตัวเลข
--      common (12): c1..c6, x1, x2, loy2569_copper/gold/lead/silver
--      good   (5) : g1..g5
--      rare   (4) : r1..r4        <- หายาก
--      vrare  (3) : v1..v3        <- หายากมาก
--      legend (4) : a1, a2, l1, l2
--      ancient(3) : a3, a4, a5
--    โค้ดเดิม: tonumber("rare") -> nil -> math.clamp(nil or 1,1,6) -> 1 = common
--    => พระ "หายาก/หายากมาก" ถูกมองเป็น "ธรรมดา" ทั้งหมด แล้วถูกปฏิเสธ
--  v30: อ่าน Tier เป็นสตริงตรง ๆ + TierName ไทย + เดาจากอักษรนำหน้า id ถ้าไม่รู้จัก
--       ระดับที่ไม่รู้จัก = ไม่รับทันที (ไม่เดา) • สีระดับดึงจาก ShopRarity
--  handBack: ต้องส่ง { i = idx, dt = ... } และ Stage ต้องเป็น "return"
--  ตัวตรวจแท้/เก๊: Variant ต้อง == Models[id].Mesh, Features.Proc = เก๊,
--                 เทียบ Checks[].Genuine/.Fake, + ธง Fake/Faults/Genuine
-- ============================================================================
if getgenv().TwoK and getgenv().TwoK.Stop then pcall(getgenv().TwoK.Stop) end

do -- ล้าง GUI เก่าที่ค้าง
	local P0 = game:GetService("Players")
	local roots = { (gethui and gethui()) or game:GetService("CoreGui") }
	local pg0 = P0.LocalPlayer:FindFirstChild("PlayerGui")
	if pg0 then roots[#roots + 1] = pg0 end
	for _, r in ipairs(roots) do
		for _, g in ipairs(r:GetChildren()) do
			pcall(function()
				if g:IsA("ScreenGui") and string.sub(g.Name, 1, 5) == "TwoK_" then g:Destroy() end
			end)
		end
	end
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local SR   = RS:FindFirstChild("ShopRemotes")
local Act  = SR and SR:FindFirstChild("Act")    -- RemoteFunction
local Look = SR and SR:FindFirstChild("Look")   -- RemoteEvent
local Push = SR and SR:FindFirstChild("Push")   -- RemoteEvent (state)

local Lab
do
	local m = RS:FindFirstChild("AmuletLab")
	if m then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then Lab = r end
	end
end
local Models = (type(Lab) == "table" and type(Lab.Models) == "table") and Lab.Models or {}

local Rarity
do
	local m = RS:FindFirstChild("ShopRarity")
	if m then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then Rarity = r end
	end
end

local TIERS = { "common", "good", "rare", "vrare", "legend", "ancient" }
local TIER_TH = { common = "ธรรมดา", good = "ดี", rare = "หายาก",
	vrare = "หายากมาก", legend = "ตำนาน", ancient = "ตำนานโบราณ" }
local TIER_BY_TH, TIER_RANK, TIER_COLOR = {}, {}, {}
for k, v in next, TIER_TH do TIER_BY_TH[v] = k end
for i, k in ipairs(TIERS) do TIER_RANK[k] = i end
for _, k in ipairs(TIERS) do
	local c
	if type(Rarity) == "table" and type(Rarity[k]) == "table" then
		c = Rarity[k].Color or Rarity[k].A
	end
	TIER_COLOR[k] = c or Color3.fromRGB(180, 190, 205)
end
TIER_COLOR.unknown = Color3.fromRGB(255, 120, 120)

local C_GREEN = Color3.fromRGB(125, 220, 150)
local C_RED   = Color3.fromRGB(255, 130, 130)
local C_YEL   = Color3.fromRGB(235, 205, 120)
local C_BLUE  = Color3.fromRGB(150, 200, 255)
local C_DIM   = Color3.fromRGB(175, 188, 208)

local Hub = {
	Running = true, Busy = false, Conns = {}, Logs = {},
	State = nil, PushCount = 0, Items = {}, CurCustomer = nil, CurCustomerIntent = nil,
	LastAct = 0, LookAt = {},
	Stat = { Buy = 0, Pass = 0, HandBack = 0, Real = 0, Fake = 0 },
	Flags = {
		Auto = true, MinConf = 90, LookTime = 3.45, CallGap = 0.6, MaxPerCustomer = 3,
		BuyRealOnly = true, PassFake = true, PassNotWanted = true,
		AutoHandBack = true, BuyPost = false,
		Tiers = { common = false, good = false, rare = false,
			vrare = true, legend = true, ancient = true },
		FilterOpen = false, BgTrans = 0.35,
	},
}
getgenv().TwoK = Hub

local function log(msg, col)
	local e = { t = os.date("%H:%M:%S"), s = tostring(msg), c = col }
	Hub.Logs[#Hub.Logs + 1] = e
	if #Hub.Logs > 250 then table.remove(Hub.Logs, 1) end
	if Hub.OnLog then pcall(Hub.OnLog, e) end
end

local function act(a1, a2)
	if not Act then return false, "ไม่พบ ShopRemotes.Act" end
	local gap = Hub.Flags.CallGap
	local d = os.clock() - Hub.LastAct
	if d < gap then task.wait(gap - d) end
	Hub.LastAct = os.clock()
	local ok, r1, r2 = pcall(function() return Act:InvokeServer(a1, a2) end)
	if not ok then return false, "err: " .. tostring(r1) end
	return (r1 == true), tostring(r2 or (r1 == true and "ok" or r1))
end

local function ensureLook(idx)
	local t = Hub.LookAt[idx]
	if not t or (os.clock() - t) > 25 then
		if Look then pcall(function() Look:FireServer(idx) end) end
		t = os.clock()
		Hub.LookAt[idx] = t
	end
	local need = Hub.Flags.LookTime
	local dt = os.clock() - t
	if dt < need then task.wait(need - dt + 0.08) end
	return os.clock() - t
end

local ACT_LABEL = { buy = "รับเช่า", pass = "ไม่รับ", handBack = "คืนพระ",
	buyPost = "รับโพสต์", machine = "ส่งเครื่อง", ["self"] = "ตรวจเอง" }

local function doAction(action, idx, extra)
	if Hub.Busy then return false, "busy" end
	Hub.Busy = true
	local dt = ensureLook(idx)
	local args = { i = idx, dt = dt }
	if type(extra) == "table" then
		for k, v in next, extra do args[k] = v end
	end
	local ok, msg = act(action, args)
	Hub.Busy = false
	if ok then
		Hub.LookAt[idx] = nil
		if action == "buy" then Hub.Stat.Buy = Hub.Stat.Buy + 1
		elseif action == "pass" then Hub.Stat.Pass = Hub.Stat.Pass + 1
		elseif action == "handBack" then Hub.Stat.HandBack = Hub.Stat.HandBack + 1 end
	end
	log(("▶ %s #%s dt=%.2fs → %s"):format(ACT_LABEL[action] or action,
		tostring(idx), dt, ok and "สำเร็จ" or ("ไม่สำเร็จ: " .. msg)),
		ok and C_GREEN or C_RED)
	task.defer(function() if Hub.RenderItems then pcall(Hub.RenderItems) end end)
	return ok, msg
end

-- ========================= ระดับพระ (จุดที่แก้) =========================
local function tierOf(id)
	local key = tostring(id or "?")
	local m = Models[key]
	if type(m) ~= "table" then
		local low = string.lower(key)
		for mid, mm in next, Models do
			if string.lower(tostring(mid)) == low then m = mm break end
		end
	end
	if type(m) ~= "table" then
		return "unknown", "ไม่รู้จักพิมพ์ " .. key, 0
	end
	local raw = m.Tier
	local t
	if type(raw) == "string" then
		if TIER_RANK[raw] then t = raw
		elseif TIER_BY_TH[raw] then t = TIER_BY_TH[raw] end
	end
	if not t and type(raw) == "number" then
		t = TIERS[math.clamp(math.floor(raw), 1, 6)]
	end
	if not t then t = TIER_BY_TH[tostring(m.TierName or "")] end
	if not t then t = TIER_BY_TH[tostring(m.Name or "")] end
	if not t then
		local p = string.sub(string.lower(key), 1, 1)
		t = ({ c = "common", g = "good", r = "rare", v = "vrare",
			l = "legend", a = "ancient", x = "common" })[p] or "unknown"
	end
	return t, tostring(m.TierName or TIER_TH[t] or t), TIER_RANK[t] or 0
end

local function analyze(it)
	local sp = (type(it) == "table" and type(it.Spec) == "table") and it.Spec or it
	local id = (type(sp) == "table" and (sp.Model or sp.id))
		or (type(it) == "table" and it.Model) or "?"
	local tier, tierName, rank = tierOf(id)
	local md = Models[tostring(id)] or Models[string.lower(tostring(id))]
	local res = { id = tostring(id), name = tostring((md and md.Name) or id),
		tier = tier, tierName = tierName, rank = rank,
		genuine = false, conf = 0, why = "ข้อมูลไม่พอ" }

	if type(sp) ~= "table" then return res end
	local mesh = md and md.Mesh

	if it.Fake == true or sp.Fake == true or it.Result == "fake" then
		res.conf, res.why = 100, "เซิร์ฟเวอร์ติดธงเก๊" return res
	end
	local faults = it.Faults or sp.Faults
	if type(faults) == "table" and next(faults) ~= nil then
		res.conf, res.why = 99, "มีรอยตำหนิ (Faults)" return res
	end
	if it.Genuine == false then
		res.conf, res.why = 99, "Genuine = false" return res
	end

	local ft = sp.Features
	if type(ft) == "table" then
		if mesh and ft.Variant ~= nil and ft.Variant ~= mesh then
			res.conf = 98
			res.why = "พิมพ์ผิด " .. tostring(ft.Variant) .. " ≠ " .. tostring(mesh)
			return res
		end
		if ft.Proc ~= nil then
			res.conf, res.why = 92, "มีขั้นตอนปลอม (Proc)" return res
		end
		if md and type(md.Checks) == "table" then
			for _, c in ipairs(md.Checks) do
				local v = ft[c.Key]
				if v ~= nil then
					if c.Genuine ~= nil and v ~= c.Genuine then
						res.conf = 97
						res.why = tostring(c.Why or c.Text or c.Key)
						return res
					end
					if c.Fake ~= nil and v == c.Fake then
						res.conf = 97
						res.why = tostring(c.Why or c.Text or c.Key)
						return res
					end
				end
			end
		end
		if mesh and ft.Variant == mesh then
			res.genuine, res.conf = true, 96
			res.why = "variant ตรงพิมพ์ " .. tostring(mesh)
			return res
		end
	end

	if it.Genuine == true then
		res.genuine, res.conf, res.why = true, 95, "Genuine = true"
	end
	return res
end

local function decide(it, count)
	local a = analyze(it)
	if count then
		if a.genuine then Hub.Stat.Real = Hub.Stat.Real + 1
		else Hub.Stat.Fake = Hub.Stat.Fake + 1 end
	end
	if a.tier == "unknown" then return false, a, "ไม่รู้จักระดับ" end
	if (not a.genuine) and Hub.Flags.PassFake then return false, a, "เก๊" end
	if a.conf < Hub.Flags.MinConf then return false, a, "มั่นใจต่ำ" end
	if not Hub.Flags.Tiers[a.tier] then return false, a, "ระดับไม่รับ (" .. a.tierName .. ")" end
	return true, a, "รับ"
end

-- ============================ ประมวลผลลูกค้า ============================
local function processCustomer()
	if not Hub.Running then return end
	local st = Hub.State
	local cus = st and st.Customer
	if not cus or not cus.Items then
		Hub.Items = {}
		if Hub.RenderItems then pcall(Hub.RenderItems) end
		return
	end
	if Hub.CurCustomer == cus.Id then return end
	Hub.CurCustomer = cus.Id

	local items = {}
	for i, it in next, cus.Items do
		items[#items + 1] = { idx = i, it = it }
	end
	table.sort(items, function(a, b)
		return (tonumber(a.idx) or 0) < (tonumber(b.idx) or 0)
	end)
	Hub.Items = items
	Hub.CurCustomerIntent = cus.Intent
	if Hub.RenderItems then pcall(Hub.RenderItems) end
	log(("ลูกค้าใหม่ (intent=%s) • %d องค์"):format(tostring(cus.Intent), #items), C_BLUE)

	if not Hub.Flags.Auto then return end
	task.spawn(function()
		local bought = 0
		for _, e in ipairs(items) do
			if not Hub.Running then break end
			local stage = string.lower(tostring(e.it.Stage or ""))
			local okBuy, a, why = decide(e.it, true)
			if stage == "return" then
				if Hub.Flags.AutoHandBack then
					log(("Stage=return #%s %s → คืนพระ"):format(tostring(e.idx), a.id), C_YEL)
					doAction("handBack", e.idx)
				end
			elseif stage == "post" then
				if Hub.Flags.BuyPost and okBuy and bought < Hub.Flags.MaxPerCustomer then
					bought = bought + 1
					log(("ตรวจ #%s %s %s แท้ %d%% → รับโพสต์")
						:format(tostring(e.idx), a.id, a.tierName, a.conf), C_GREEN)
					doAction("buyPost", e.idx)
				elseif Hub.Flags.PassNotWanted then
					doAction("pass", e.idx)
				end
			elseif stage == "offer" then
				if okBuy and bought < Hub.Flags.MaxPerCustomer then
					bought = bought + 1
					log(("ตรวจ #%s %s = %s • แท้ %d%% (%s) → รับ")
						:format(tostring(e.idx), a.id, a.tierName, a.conf, a.name), C_GREEN)
					doAction("buy", e.idx)
				elseif Hub.Flags.PassNotWanted then
					log(("ปฏิเสธ #%s %s (%s • %s %d%%) • %s")
						:format(tostring(e.idx), a.id, a.tierName,
							a.genuine and "แท้" or "เก๊", a.conf, why), C_DIM)
					doAction("pass", e.idx)
				end
			end
		end
		log("จบรอบลูกค้า: รับ " .. bought .. " องค์", C_BLUE)
	end)
end

-- ================================== UI ==================================
local HUI = (gethui and gethui()) or game:GetService("CoreGui")
local cam = workspace.CurrentCamera
local vp = (cam and cam.ViewportSize) or Vector2.new(1024, 600)
local SW = math.clamp(math.floor(vp.X * 0.94), 430, 1400)
local SH = math.clamp(math.floor(vp.Y * 0.90), 260, 900)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in next, props or {} do pcall(function() o[k] = v end) end
	if parent then o.Parent = parent end
	return o
end
local function addStroke(obj, th)
	local s = Instance.new("UIStroke")
	s.Thickness = th or 1.3
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Transparency = 0.12
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = obj
	return s
end

local gui = new("ScreenGui", { Name = "TwoK_Hub_v32", ResetOnSpawn = false,
	IgnoreGuiInset = true, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, HUI)

local main = new("Frame", { Name = "Main", BackgroundColor3 = Color3.fromRGB(16, 18, 24),
	BackgroundTransparency = Hub.Flags.BgTrans, BorderSizePixel = 0,
	Position = UDim2.fromOffset(math.max(0, math.floor((vp.X - SW) / 2)),
		math.max(0, math.floor((vp.Y - SH) / 2))),
	Size = UDim2.fromOffset(SW, SH), ClipsDescendants = true }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
new("UIStroke", { Color = Color3.fromRGB(90, 140, 200), Thickness = 1.2, Transparency = 0.25 }, main)

local bar = new("Frame", { Name = "Bar", BackgroundColor3 = Color3.fromRGB(30, 36, 48),
	BackgroundTransparency = 0.15, Size = UDim2.new(1, 0, 0, 34), BorderSizePixel = 0 }, main)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, bar)

local title = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -170, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13.5,
	TextColor3 = Color3.fromRGB(236, 242, 255), TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true, Text = "ถนนพระเครื่อง — Hub v32" }, bar)
addStroke(title)

local function barBtn(txt, x, w)
	local b = new("TextButton", { BackgroundColor3 = Color3.fromRGB(44, 52, 66),
		BackgroundTransparency = 0.15, Position = UDim2.new(1, -x, 0, 4),
		Size = UDim2.fromOffset(w or 30, 26), Font = Enum.Font.GothamBold, TextSize = 14,
		BorderSizePixel = 0, TextColor3 = Color3.fromRGB(222, 232, 246), Text = txt }, bar)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	return b
end
local btnFilter  = barBtn("⚙", 102)
local btnRefresh = barBtn("🔁", 136)
local btnMin     = barBtn("—", 68)
local btnClose   = barBtn("✕", 34)

local body = new("Frame", { Name = "Body", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(6, 40), Size = UDim2.new(1, -12, 1, -46) }, main)

local function newColumn(name)
	local col = new("Frame", { Name = name, BackgroundTransparency = 1 }, body)
	local head = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold, TextSize = 12.5, TextWrapped = true,
		TextColor3 = Color3.fromRGB(170, 205, 245),
		TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, col)
	addStroke(head)
	local sc = new("ScrollingFrame", { Name = "Scroll", BackgroundColor3 = Color3.fromRGB(22, 26, 34),
		BackgroundTransparency = 0.4, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 1, -22), ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y }, col)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, sc)
	local list = new("Frame", { Name = "List", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 0) }, sc)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	return col, sc, list, head
end

local colFilter, filterSc, filterList = newColumn("ColFilter")
local colLog, logSc, logList, logHead = newColumn("ColLog")
local colList, listSc, listRows, listHead = newColumn("ColList")
colFilter.Visible = Hub.Flags.FilterOpen
logHead.Text = "📋 บันทึก"
listHead.Text = "🪙 รายการพระลูกค้า"

local function layout()
	local bw, bh = body.AbsoluteSize.X, body.AbsoluteSize.Y
	if bw <= 0 then bw, bh = SW - 12, SH - 46 end
	colFilter.Visible = Hub.Flags.FilterOpen
	if Hub.Flags.FilterOpen then
		colFilter.Position = UDim2.fromOffset(0, 0)
		colFilter.Size = UDim2.fromOffset(math.min(240, math.max(150, bw * 0.32)), bh)
		local fw = colFilter.Size.X.Offset
		local rest = math.max(180, bw - fw - 6)
		local lw = math.max(110, math.floor(rest * 0.42))
		colLog.Position = UDim2.fromOffset(fw + 6, 0)
		colLog.Size = UDim2.fromOffset(lw, bh)
		colList.Position = UDim2.fromOffset(fw + lw + 12, 0)
		colList.Size = UDim2.fromOffset(math.max(110, rest - lw), bh)
	else
		local lw = math.max(110, math.floor(bw * 0.42))
		colLog.Position = UDim2.fromOffset(0, 0)
		colLog.Size = UDim2.fromOffset(lw, bh)
		colList.Position = UDim2.fromOffset(lw + 6, 0)
		colList.Size = UDim2.fromOffset(math.max(110, bw - lw - 6), bh)
	end
end

do -- ลาก / ย่อ-ขยาย
	local dragging, startPos, startInput = false, nil, nil
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startInput = true, main.Position, input.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - startInput
			main.Position = UDim2.fromOffset(
				math.clamp(math.floor(startPos.X.Offset + d.X), -main.AbsoluteSize.X + 70, vp.X - 70),
				math.clamp(math.floor(startPos.Y.Offset + d.Y), 0, vp.Y - 36))
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

local grip = new("TextButton", { Name = "Grip", BackgroundTransparency = 1, Text = "◢",
	Position = UDim2.new(1, -22, 1, -22), Size = UDim2.fromOffset(22, 22),
	Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = Color3.fromRGB(150, 180, 220) }, main)
do
	local rs, rsStart, rsSize = false, nil, nil
	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			rs, rsStart, rsSize = true, input.Position, main.Size
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not rs then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - rsStart
			main.Size = UDim2.fromOffset(
				math.clamp(math.floor(rsSize.X.Offset + d.X), 420, vp.X),
				math.clamp(math.floor(rsSize.Y.Offset + d.Y), 240, vp.Y))
			layout()
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then rs = false end
	end)
end

-- ------------------------------ บันทึก ------------------------------
local logSeq = 0
Hub.OnLog = function(e)
	logSeq = logSeq + 1
	local lbl = new("TextLabel", { Name = "L" .. logSeq, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.GothamMedium, TextSize = 12.5, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = logSeq,
		TextColor3 = e.c or Color3.fromRGB(215, 224, 238),
		Text = "[" .. e.t .. "] " .. e.s }, logList)
	addStroke(lbl, 1.2)
	if logSeq > 140 then
		local first = logList:FindFirstChild("L" .. (logSeq - 140))
		if first then first:Destroy() end
	end
	if logSc then
		task.defer(function() logSc.CanvasPosition = Vector2.new(0, math.max(0, logList.AbsoluteSize.Y)) end)
	end
end

-- --------------------------- รายการลูกค้า ---------------------------
local STAGE_TH = { offer = "เสนอขาย", ["return"] = "รอคืนพระ",
	post = "รอลงป้าย", done = "จบแล้ว" }

local function renderItems()
	for _, c in ipairs(listRows:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local items = Hub.Items or {}
	local cnt = 0
	for _, e in ipairs(items) do
		if decide(e.it, false) then cnt = cnt + 1 end
	end
	listHead.Text = ("🪙 รายการพระลูกค้า (%d องค์ • รับได้ %d)"):format(#items, cnt)
