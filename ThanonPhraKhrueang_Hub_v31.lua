-- ============================================================================
--  ถนนพระเครื่อง — Hub v31  (= v30 + ระบบประเมินแท้/เก๊)
--
--  สิ่งที่เพิ่มจาก v30:
--   1) การ์ดพระแต่ละองค์มีปุ่ม "✔ แท้ (n)" / "✖ เก๊ (n)"  ← กดประเมินเองได้ทันที
--      n = จำนวนโหวตที่เคยประเมินไว้ (แยกเป็น 2 ชั้น: ระดับ "พิมพ์" และ "ลาย" ขององค์นั้น)
--   2) จำผลประเมินลงไฟล์ TwoK_v30_rating.json (พิมพ์/ลาย + จำนวนโหวต) → เปิดรอบหน้าใช้ต่อได้
--      ลาย = ซิกเนเจอร์ของ Features ทั้งก้อน (Variant/Proc/ค่าทุก check) จึงจำ "พิมพ์ปลอมตัวนี้" ได้
--   3) analyze() เชื่อผลประเมินของคุณก่อน (เปิด/ปิดได้, ตั้งจำนวนโหวตขั้นต่ำได้ 1-3)
--      - เจอลายเดิม/พิมพ์เดิมที่คุณเคยกดไว้ → ตัดสินตามคุณทันที (ไม่ต้องกดซ้ำ)
--      - ยังแสดงผลตัวตรวจอัตโนมัติเดิมไว้เทียบในบันทึก ("เดิม: เก๊ 96%")
--   4) ตัวเลือก "ประเมินแล้วทำทันที": กด ✔แท้ = ยิง buy, กด ✖เก๊ = ยิง pass ทันที
--   5) เครื่องมือ: 🧠 ดูสถิติการประเมิน • 🗑 ล้างผลประเมิน • 💾 บันทึกเดี๋ยวนี้
--
--  ของเดิมทั้งหมดคงอยู่: ตัวกรองซ่อน (⚙) • บันทึก • รายการพระลูกค้า • ระดับพระอ่านจาก
--  Lab.Models[id].Tier (สตริง) • handBack ต้องมี dt • Stage: offer/return/post
-- ============================================================================
if getgenv().TwoK and getgenv().TwoK.Stop then pcall(getgenv().TwoK.Stop) end

do -- ล้าง GUI เก่า (v20–v31)
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
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local SR   = RS:FindFirstChild("ShopRemotes")
local Act  = SR and SR:FindFirstChild("Act")
local Look = SR and SR:FindFirstChild("Look")
local Push = SR and SR:FindFirstChild("Push")

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
		-- ระบบประเมิน
		TrustRating = true, MinVotes = 1, RateActs = false, ShowRating = true,
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

-- ===========================================================================
--  ระบบประเมิน (Rating) — จำผล "แท้/เก๊" ที่ผู้เล่นกดไว้
--   Rating.models[id]   = { R = โหวตแท้, F = โหวตเก๊ }   (ระดับพิมพ์)
--   Rating.sigs[sig]    = { R, F }                        (ระดับลาย/ซิกเนเจอร์ของ Features)
--   Rating.manual[key]  = { v = "real"/"fake", id, sig }  (รายองค์ของลูกค้าคนนี้)
-- ===========================================================================
local RATE_FILE = "TwoK_v30_rating.json"
local Rating = { models = {}, sigs = {}, manual = {}, total = 0 }
local RATE_DIRTY = false

local function countKeys(t)
	local n = 0
	for _ in next, t do n = n + 1 end
	return n
end

local function rateKeyOf(cusId, idx)
	return tostring(cusId or "?") .. ":" .. tostring(idx)
end

local function saveRating()
	RATE_DIRTY = false
	pcall(function()
		if not writefile then return end
		writefile(RATE_FILE, HttpService:JSONEncode({
			models = Rating.models, sigs = Rating.sigs, total = Rating.total,
		}))
	end)
end

local function loadRating()
	pcall(function()
		if not (isfile and isfile(RATE_FILE)) then return end
		local ok, d = pcall(function() return HttpService:JSONDecode(readfile(RATE_FILE)) end)
		if ok and type(d) == "table" then
			if type(d.models) == "table" then Rating.models = d.models end
			if type(d.sigs) == "table" then Rating.sigs = d.sigs end
			Rating.total = tonumber(d.total) or 0
		end
	end)
end

-- ซิกเนเจอร์ของ "ลาย" = ค่า Features ทุกตัวเรียงตามชื่อ (จำได้ว่าเก๊ลายไหน/พิมพ์ปลอมตัวไหน)
local function sigOf(sp, id)
	local ft = type(sp) == "table" and sp.Features
	if type(ft) ~= "table" then return nil end
	local parts = {}
	for k, v in next, ft do
		local tv = type(v)
		if tv == "boolean" or tv == "string" or tv == "number" then
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
		end
	end
	if #parts == 0 then return nil end
	table.sort(parts)
	local s = tostring(id) .. "|" .. table.concat(parts, "&")
	if #s > 600 then s = string.sub(s, 1, 600) end
	return s
end

local function bucket(t, key)
	if not key then return nil end
	local e = t[key]
	if type(e) ~= "table" then
		e = { R = 0, F = 0 }
		t[key] = e
	end
	return e
end

local function deltaVote(id, sig, verdict, d)
	local m = bucket(Rating.models, tostring(id))
	local s = bucket(Rating.sigs, sig)
	local field = (verdict == "real") and "R" or "F"
	if m then m[field] = math.max(0, (tonumber(m[field]) or 0) + d) end
	if s then s[field] = math.max(0, (tonumber(s[field]) or 0) + d) end
	Rating.total = math.max(0, (tonumber(Rating.total) or 0) + d)
	RATE_DIRTY = true
end

-- คืน: verdict, conf, source, R, F  (nil ถ้ายังไม่มีผล/โหวตไม่ถึงขั้นต่ำ)
local function voteOf(id, sig)
	local need = math.max(1, math.floor(tonumber(Hub.Flags.MinVotes) or 1))
	local function pick(e, src)
		if type(e) ~= "table" then return nil end
		local r, f = tonumber(e.R) or 0, tonumber(e.F) or 0
		if (r + f) < need or r == f then return nil end
		local verdict = (r > f) and "real" or "fake"
		local conf = math.min(99, 88 + math.floor(10 * math.abs(r - f) / (r + f)))
		return verdict, conf, src, r, f
	end
	local v, c, s, r, f = pick(sig and Rating.sigs[sig] or nil, "ลาย")
	if v then return v, c, s, r, f end
	v, c, s, r, f = pick(Rating.models[tostring(id)], "พิมพ์")
	if v then return v, c, s, r, f end
	return nil
end

-- กดประเมินรายองค์ (กดซ้ำค่าเดิม = ไม่เปลี่ยนอะไร, กดสลับ = ปรับโหวตให้ถูกต้อง)
local function setManual(key, id, sig, verdict)
	local cur = Rating.manual[key]
	if type(cur) == "table" and cur.v == verdict then return false end
	if type(cur) == "table" then
		deltaVote(cur.id, cur.sig, cur.v, -1)
	end
	Rating.manual[key] = { v = verdict, id = tostring(id), sig = sig }
	deltaVote(id, sig, verdict, 1)
	return true
end

local function pruneManual(keepPrefix)
	local keep, keepN = {}, 0
	for k in next, Rating.manual do
		if string.sub(k, 1, #keepPrefix) == keepPrefix then keep[k] = true keepN = keepN + 1 end
	end
	local n = 0
	for k in next, Rating.manual do
		if not keep[k] then
			n = n + 1
			if n > 120 then Rating.manual[k] = nil end
		end
	end
	return keepN
end

-- ========================= ระดับพระ =========================
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

-- ================== ตัวตรวจ (โครงสร้างจริง + ผลประเมินของคุณ) ==================
local function structural(it, sp, md, res)
	if type(sp) ~= "table" then return end
	local mesh = md and md.Mesh
	if it.Fake == true or sp.Fake == true or it.Result == "fake" then
		res.conf, res.why = 100, "เซิร์ฟเวอร์ติดธงเก๊"
		return
	end
	local faults = it.Faults or sp.Faults
	if type(faults) == "table" and next(faults) ~= nil then
		res.conf, res.why = 99, "มีรอยตำหนิ (Faults)"
		return
	end
	if it.Genuine == false then
		res.conf, res.why = 99, "Genuine = false"
		return
	end
	local ft = sp.Features
	if type(ft) == "table" then
		if mesh and ft.Variant ~= nil and ft.Variant ~= mesh then
			res.conf = 98
			res.why = "พิมพ์ผิด " .. tostring(ft.Variant) .. " ≠ " .. tostring(mesh)
			return
		end
		if ft.Proc ~= nil then
			res.conf, res.why = 92, "มีขั้นตอนปลอม (Proc)"
			return
		end
		if md and type(md.Checks) == "table" then
			for _, c in ipairs(md.Checks) do
				local v = ft[c.Key]
				if v ~= nil then
					if c.Genuine ~= nil and v ~= c.Genuine then
						res.conf = 97
						res.why = tostring(c.Why or c.Text or c.Key)
						return
					end
					if c.Fake ~= nil and v == c.Fake then
						res.conf = 97
						res.why = tostring(c.Why or c.Text or c.Key)
						return
					end
				end
			end
		end
		if mesh and ft.Variant == mesh then
			res.genuine, res.conf = true, 96
			res.why = "variant ตรงพิมพ์ " .. tostring(mesh)
			return
		end
	end
	if it.Genuine == true then
		res.genuine, res.conf, res.why = true, 95, "Genuine = true"
	end
end

local function analyze(it)
	local sp = (type(it) == "table" and type(it.Spec) == "table") and it.Spec or it
	local id = (type(sp) == "table" and (sp.Model or sp.id))
		or (type(it) == "table" and it.Model) or "?"
	local tier, tierName, rank = tierOf(id)
	local md = Models[tostring(id)] or Models[string.lower(tostring(id))]
	local res = { id = tostring(id), name = tostring((md and md.Name) or id),
		tier = tier, tierName = tierName, rank = rank,
		genuine = false, conf = 0, why = "ข้อมูลไม่พอ", sig = sigOf(sp, id) }

	structural(it, sp, md, res)
	res.auto = { genuine = res.genuine, conf = res.conf, why = res.why }

	if Hub.Flags.TrustRating then
		local v, c, src, r, f = voteOf(res.id, res.sig)
		if v then
			res.genuine = (v == "real")
			res.conf = c
			res.why = ("ประเมินของคุณ [%s แท้%d/เก๊%d] • อัตโนมัติ: %s %d%%"):format(
				tostring(src), r, f,
				res.auto.genuine and "แท้" or "เก๊", res.auto.conf)
			res.rated = true
			res.rateSrc = src
		end
	end
	return res
end

local function decide(it, key, count)
	local a = analyze(it)
	if count then
		if a.genuine then Hub.Stat.Real = Hub.Stat.Real + 1
		else Hub.Stat.Fake = Hub.Stat.Fake + 1 end
	end
	local man = key and Rating.manual[key]
	if type(man) == "table" then
		a.manual = true
		a.genuine = (man.v == "real")
		a.conf = 100
		a.why = "คุณกดประเมินเอง: " .. (man.v == "real" and "แท้" or "เก๊")
		if a.tier ~= "unknown" and not Hub.Flags.Tiers[a.tier] then
			return false, a, "ระดับไม่รับ (" .. a.tierName .. ")"
		end
		return a.genuine, a, a.why
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
	pruneManual(rateKeyOf(cus.Id, ""))

	local items = {}
	for i, it in next, cus.Items do
		items[#items + 1] = { idx = i, it = it, key = rateKeyOf(cus.Id, i) }
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
			local okBuy, a, why = decide(e.it, e.key, true)
			if stage == "return" then
				if Hub.Flags.AutoHandBack then
					log(("Stage=return #%s %s → คืนพระ"):format(tostring(e.idx), a.id), C_YEL)
					doAction("handBack", e.idx)
				end
			elseif stage == "post" then
				if Hub.Flags.BuyPost and okBuy and bought < Hub.Flags.MaxPerCustomer then
					bought = bought + 1
					log(("ตรวจ #%s %s %s %s %d%% → รับโพสต์")
						:format(tostring(e.idx), a.id, a.tierName,
							a.genuine and "แท้" or "เก๊", a.conf), C_GREEN)
					doAction("buyPost", e.idx)
				elseif Hub.Flags.PassNotWanted then
					doAction("pass", e.idx)
				end
			elseif stage == "offer" then
				if okBuy and bought < Hub.Flags.MaxPerCustomer then
					bought = bought + 1
					log(("ตรวจ #%s %s %s %s %d%% (%s) → รับ")
						:format(tostring(e.idx), a.id, a.tierName,
							a.genuine and "แท้" or "เก๊", a.conf, a.name), C_GREEN)
					doAction("buy", e.idx)
				elseif Hub.Flags.PassNotWanted then
					log(("ปฏิเสธ #%s %s (%s %s %d%%) • %s")
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

local gui = new("ScreenGui", { Name = "TwoK_Hub_v31", ResetOnSpawn = false,
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
	TextWrapped = true, Text = "ถนนพระเครื่อง — Hub v31" }, bar)
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
		task.defer(function()
			logSc.CanvasPosition = Vector2.new(0, math.max(0, logList.AbsoluteSize.Y))
		end)
	end
end

-- --------------------------- รายการลูกค้า ---------------------------
local STAGE_TH = { offer = "เสนอขาย", ["return"] = "รอคืนพระ",
	post = "รอลงป้าย", done = "จบแล้ว" }
local H_CARD = 104

local function renderItems()
	for _, c in ipairs(listRows:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local items = Hub.Items or {}
	local canBuy = 0
	for _, e in ipairs(items) do
		if decide(e.it, e.key, false) then canBuy = canBuy + 1 end
	end
	local ratedN = countKeys(Rating.manual)
	listHead.Text = ("🪙 รายการลูกค้า (%d องค์ • รับได้ %d • ประเมินแล้ว %d)")
		:format(#items, canBuy, ratedN)

	if #items == 0 then
		new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46),
			Font = Enum.Font.Gotham, TextSize = 12.5, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
			TextColor3 = Color3.fromRGB(160, 172, 192),
			Text = "ยังไม่มีรายการ — ยืนที่ร้าน รอลูกค้า แล้วกด 🔁\nกด ✔แท้ / ✖เก๊ บนการ์ดเพื่อสอนระบบได้" },
			listRows)
		return
	end

	local intent = Hub.CurCustomerIntent
	for n, e in ipairs(items) do
		local a = analyze(e.it)
		local stage = string.lower(tostring(e.it.Stage or "?"))
		local want = Hub.Flags.Tiers[a.tier] == true
		local okBuy = a.genuine and want and a.conf >= Hub.Flags.MinConf
		local col = okBuy and C_GREEN or (want and C_YEL or C_RED)
		local tcol = TIER_COLOR[a.tier] or C_DIM

		local row = new("Frame", { Name = "R" .. n, BackgroundColor3 = Color3.fromRGB(30, 34, 44),
			BackgroundTransparency = 0.28, Size = UDim2.new(1, 0, 0, H_CARD),
			BorderSizePixel = 0, LayoutOrder = n }, listRows)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		new("Frame", { Name = "Accent", BackgroundColor3 = col, BackgroundTransparency = 0.05,
			Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0 }, row)

		local t1 = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -14, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12.5,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(236, 242, 252),
			Text = ("#%s %s • %s"):format(tostring(e.idx), a.id, a.name) }, row)
		addStroke(t1)

		local t2 = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 19),
			Size = UDim2.new(1, -14, 0, 15), Font = Enum.Font.GothamBold, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = tcol,
			Text = ("ระดับ: %s [%s] • %s %d%%%s"):format(a.tierName, a.tier,
				a.genuine and "แท้" or "เก๊", a.conf,
				a.rated and " • จากผลประเมิน" or "") }, row)
		addStroke(t2)

		local t3 = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 35),
			Size = UDim2.new(1, -14, 0, 14), Font = Enum.Font.Gotham, TextSize = 11.5,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C_DIM,
			Text = ("%s • %s%s"):format(a.why, STAGE_TH[stage] or stage,
				want and " • ✔ อยู่ในระดับที่รับ" or " • ✖ ไม่อยู่ในระดับที่เลือก") }, row)

		-- ปุ่มกระทำ (รับ / ไม่รับ / คืนพระ ...)
		local btns = {}
		if stage == "return" then
			btns = { { "คืนพระ", "handBack", Color3.fromRGB(52, 132, 116) } }
		elseif stage == "post" then
			btns = { { "รับโพสต์", "buyPost", Color3.fromRGB(46, 130, 84) },
				{ "ไม่รับ", "pass", Color3.fromRGB(126, 56, 56) } }
		elseif stage == "offer" then
			btns = { { "รับ", "buy", Color3.fromRGB(46, 130, 84) },
				{ "ไม่รับ", "pass", Color3.fromRGB(126, 56, 56) } }
			if intent ~= "sell" then
				btns[#btns + 1] = { "เครื่อง", "machine", Color3.fromRGB(54, 92, 132) }
			end
		end
		local nb = #btns
		for k = 1, nb do
			local txt, action, color = btns[k][1], btns[k][2], btns[k][3]
			local bb = new("TextButton", { BackgroundColor3 = color, BorderSizePixel = 0,
				Position = UDim2.new((k - 1) / nb, 4, 0, 50),
				Size = UDim2.new(1 / nb, -8, 0, 22), Font = Enum.Font.GothamBold,
				TextSize = 12.5, TextColor3 = Color3.fromRGB(240, 250, 245), Text = txt }, row)
			new("UICorner", { CornerRadius = UDim.new(0, 5) }, bb)
			bb.MouseButton1Click:Connect(function()
				task.spawn(function() doAction(action, e.idx) end)
			end)
		end

		-- ★ ปุ่มประเมิน: ✔ แท้ / ✖ เก๊
		if Hub.Flags.ShowRating then
			local mrate = Rating.models[a.id]
			local mr = tonumber(mrate and mrate.R) or 0
			local mf = tonumber(mrate and mrate.F) or 0
			local srate = a.sig and Rating.sigs[a.sig]
			local sr = tonumber(srate and srate.R) or 0
			local sf = tonumber(srate and srate.F) or 0
			local cur = Rating.manual[e.key]
			local curV = type(cur) == "table" and cur.v or nil

			local function mkRateBtn(verdict, txt, baseCol, selCol, x, w)
				local sel = (curV == verdict)
				local b = new("TextButton", { BackgroundColor3 = sel and selCol or baseCol,
					BorderSizePixel = 0, Position = UDim2.new(x, 4, 0, 76),
					Size = UDim2.new(w, -8, 0, 24), Font = Enum.Font.GothamBold,
					TextSize = 12.5, TextColor3 = Color3.fromRGB(240, 250, 245), Text = txt }, row)
				new("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
				if sel then
					new("UIStroke", { Color = Color3.fromRGB(255, 255, 255),
						Thickness = 1.4, Transparency = 0.25 }, b)
				end
				b.MouseButton1Click:Connect(function()
					task.spawn(function()
						local changed = setManual(e.key, a.id, a.sig, verdict)
						if changed then
							log(("★ ประเมิน #%s %s → %s (พิมพ์ %d/%d • ลาย %d/%d)"):format(
								tostring(e.idx), a.id, verdict == "real" and "แท้" or "เก๊",
								mr + (verdict == "real" and 1 or 0), mf + (verdict == "fake" and 1 or 0),
								sr + (verdict == "real" and 1 or 0), sf + (verdict == "fake" and 1 or 0)),
								verdict == "real" and C_GREEN or C_RED)
							if Hub.Flags.RateActs and (stage == "offer" or stage == "post") then
								doAction(verdict == "real"
									and (stage == "post" and "buyPost" or "buy") or "pass", e.idx)
							end
							if Hub.RenderItems then pcall(Hub.RenderItems) end
						else
							log(("★ #%s %s ประเมินซ้ำ (%s) — ไม่เปลี่ยน")
								:format(tostring(e.idx), a.id,
									verdict == "real" and "แท้" or "เก๊"), C_DIM)
						end
					end)
				end)
				return b
			end

			mkRateBtn("real", ("✔ แท้ (%d)"):format(mr),
				Color3.fromRGB(40, 96, 72), Color3.fromRGB(58, 168, 118), 0, 0.5)
			mkRateBtn("fake", ("✖ เก๊ (%d)"):format(mf),
				Color3.fromRGB(102, 50, 50), Color3.fromRGB(184, 74, 74), 0.5, 0.5)
		end
	end
end
Hub.RenderItems = renderItems

-- ------------------------ ตัวกรอง (ซ่อน กด ⚙) ------------------------
do
	local seq = 0
	local function order() seq = seq + 1 return seq end
	local function mkLabel(txt, col, h)
		return new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 18),
			Font = Enum.Font.GothamBold, TextSize = 12.5, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order(),
			TextColor3 = col or Color3.fromRGB(150, 200, 245), Text = txt }, filterList)
	end
	local function mkToggle(label, key, h)
		local b = new("TextButton", { BackgroundColor3 = Color3.fromRGB(54, 46, 48),
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h or 28),
			Font = Enum.Font.GothamMedium, TextSize = 12.5,
			TextColor3 = Color3.fromRGB(226, 234, 246), LayoutOrder = order(), Text = "" }, filterList)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		local function upd()
			local v = Hub.Flags[key] == true
			b.Text = (v and "✔ " or "✖ ") .. label
			b.BackgroundColor3 = v and Color3.fromRGB(44, 96, 72) or Color3.fromRGB(54, 46, 48)
		end
		b.MouseButton1Click:Connect(function()
			Hub.Flags[key] = not Hub.Flags[key]
			upd()
			renderItems()
			log(label .. " = " .. tostring(Hub.Flags[key]))
		end)
		upd()
		return b
	end
	local function mkBtn(txt, h, cb)
		local b = new("TextButton", { BackgroundColor3 = Color3.fromRGB(52, 62, 82),
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h or 30),
			Font = Enum.Font.GothamBold, TextSize = 12.5,
			TextColor3 = Color3.fromRGB(236, 244, 255), LayoutOrder = order(), Text = txt }, filterList)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		b.MouseButton1Click:Connect(cb)
		return b
	end

	mkLabel("ระดับที่รับ (ซ่อนอยู่ กด ⚙)", Color3.fromRGB(255, 205, 130))
	for _, k in ipairs(TIERS) do
		local b = new("TextButton", { BackgroundColor3 = Color3.fromRGB(54, 46, 48),
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 26),
			Font = Enum.Font.GothamMedium, TextSize = 12.5,
			TextColor3 = Color3.fromRGB(226, 234, 246), LayoutOrder = order(), Text = "" }, filterList)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		local function upd()
			local v = Hub.Flags.Tiers[k] == true
			b.Text = (v and "✔ " or "✖ ") .. (TIER_TH[k] or k) .. " (" .. k .. ")"
			b.BackgroundColor3 = v and Color3.fromRGB(40, 92, 100) or Color3.fromRGB(54, 46, 48)
		end
		b.MouseButton1Click:Connect(function()
			Hub.Flags.Tiers[k] = not Hub.Flags.Tiers[k]
			upd()
			renderItems()
			log("ระดับ " .. (TIER_TH[k] or k) .. " = "
				.. (Hub.Flags.Tiers[k] and "รับ" or "ไม่รับ"))
		end)
		upd()
	end

	mkLabel("การทำงาน")
	mkToggle("อัตโนมัติ", "Auto")
	mkToggle("คืนพระอัตโนมัติ (Stage=return)", "AutoHandBack")
	mkToggle("เก๊ = ปฏิเสธ", "PassFake")
	mkToggle("นอกระดับ = ปฏิเสธ", "PassNotWanted")
	mkToggle("ลงป้ายขาย (buyPost)", "BuyPost")

	mkLabel("ระบบประเมิน (แท้/เก๊)", Color3.fromRGB(190, 235, 190))
	mkToggle("เชื่อผลประเมินก่อนตัวตรวจ", "TrustRating")
	mkToggle("ประเมินแล้วทำทันที (รับ/ปฏิเสธ)", "RateActs")
	mkToggle("แสดงปุ่มประเมินบนการ์ด", "ShowRating")
	local btnMinVotes
	btnMinVotes = mkBtn("", 28, function()
		local n = math.floor(tonumber(Hub.Flags.MinVotes) or 1) + 1
		if n > 3 then n = 1 end
		Hub.Flags.MinVotes = n
		btnMinVotes.Text = "โหวตขั้นต่ำก่อนเชื่อผล: " .. n .. " ครั้ง (กดเปลี่ยน)"
		renderItems()
	end)
	btnMinVotes.Text = "โหวตขั้นต่ำก่อนเชื่อผล: " .. tostring(Hub.Flags.MinVotes) .. " ครั้ง (กดเปลี่ยน)"

	mkLabel("เครื่องมือ")
	mkBtn("📊 ทดสอบระดับทั้ง 31 พิมพ์", 30, function()
		local per, tot = {}, 0
		for id in next, Models do
			local t, th = tierOf(id)
			per[th] = (per[th] or 0) + 1
			tot = tot + 1
		end
		local parts = {}
		for _, k in ipairs(TIERS) do
			parts[#parts + 1] = (TIER_TH[k] or k) .. "=" .. tostring(per[TIER_TH[k] or k] or 0)
		end
		log(("ระดับที่อ่านได้ (%d พิมพ์): %s"):format(tot, table.concat(parts, " • ")),
			Color3.fromRGB(150, 215, 255))
	end)
	mkBtn("🧠 สถิติการประเมิน", 30, function()
		local cnt, top = 0, {}
		for id, e in next, Rating.models do
			local r, f = tonumber(e.R) or 0, tonumber(e.F) or 0
			if r + f > 0 then
				cnt = cnt + 1
				top[#top + 1] = { id = id, r = r, f = f, t = r + f }
			end
		end
		table.sort(top, function(x, y) return x.t > y.t end)
		log(("ประเมินไว้: %d พิมพ์ • %d ลาย • %d โหวต")
			:format(cnt, countKeys(Rating.sigs), Rating.total), C_BLUE)
		for i = 1, math.min(6, #top) do
			log(("  %s → แท้ %d / เก๊ %d"):format(top[i].id, top[i].r, top[i].f), C_DIM)
		end
	end)
	mkBtn("💾 บันทึกผลประเมินเดี๋ยวนี้", 28, function()
		saveRating()
		log("บันทึกผลประเมินลง " .. RATE_FILE .. " แล้ว", C_BLUE)
	end)
	mkBtn("🗑 ล้างผลประเมินทั้งหมด", 28, function()
		Rating.models, Rating.sigs, Rating.manual = {}, {}, {}
		Rating.total = 0
		saveRating()
		renderItems()
		log("ล้างผลประเมินทั้งหมดแล้ว", C_RED)
	end)
	mkBtn("🎯 คืนพระตอนนี้ (Stage=return)", 30, function()
		task.spawn(function()
			local found = false
			local stl = {}
			for _, e in ipairs(Hub.Items or {}) do
				stl[#stl + 1] = tostring(e.idx) .. "=" .. tostring(e.it.Stage)
				if string.lower(tostring(e.it.Stage or "")) == "return" then
					found = true
					log("พบ Stage=return #" .. tostring(e.idx) .. " → คืนพระ", C_YEL)
					doAction("handBack", e.idx)
					break
				end
			end
			if not found then
				log("ยังไม่มี Stage=return (มี: "
					.. (#stl > 0 and table.concat(stl, " ") or "ไม่มีลูกค้า") .. ")", C_RED)
			end
		end)
	end)
	mkBtn("🔁 อ่านรายการลูกค้าใหม่", 30, function()
		Hub.CurCustomer = nil
		log("อ่านรายการใหม่เอง (Push #" .. Hub.PushCount .. ")")
		task.spawn(processCustomer)
	end)
	mkBtn("🧹 ล้างบันทึก", 28, function()
		for _, c in ipairs(logList:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		Hub.Logs = {}
		log("ล้างบันทึกแล้ว")
	end)
end

btnFilter.MouseButton1Click:Connect(function()
	Hub.Flags.FilterOpen = not Hub.Flags.FilterOpen
	layout()
end)
btnRefresh.MouseButton1Click:Connect(function()
	Hub.CurCustomer = nil
	log("🔁 อ่านใหม่ (Push #" .. Hub.PushCount
		.. (Hub.State and " • มี state" or " • ยังไม่มี state") .. ")")
	task.spawn(processCustomer)
	if Hub.RenderItems then pcall(Hub.RenderItems) end
end)
btnMin.MouseButton1Click:Connect(function()
	local min = not (main:GetAttribute("Min") == true)
	if min then
		main:SetAttribute("H", main.Size.Y.Offset)
		main.Size = UDim2.fromOffset(main.Size.X.Offset, 34)
	else
		main.Size = UDim2.fromOffset(main.Size.X.Offset, main:GetAttribute("H") or SH)
	end
	main:SetAttribute("Min", min)
	body.Visible = not min
	grip.Visible = not min
	if not min then layout() end
end)
btnClose.MouseButton1Click:Connect(function() pcall(function() Hub.Stop() end) end)

-- ------------------------------ Push hook ------------------------------
if Push then
	local conn = Push.OnClientEvent:Connect(function(...)
		local argc = select("#", ...)
		for i = 1, argc do
			local v = select(i, ...)
			if type(v) == "table" then
				if v.Customer or v.Market or v.Safe or v.Showroom or v.Scans then
					Hub.State = v
					Hub.PushCount = Hub.PushCount + 1
					logHead.Text = "📋 บันทึก (Push " .. Hub.PushCount .. ")"
					task.spawn(processCustomer)
					return
				end
				for _, w in next, v do
					if type(w) == "table" and (w.Customer or w.Market or w.Scans) then
						Hub.State = w
						Hub.PushCount = Hub.PushCount + 1
						logHead.Text = "📋 บันทึก (Push " .. Hub.PushCount .. ")"
						task.spawn(processCustomer)
						return
					end
				end
			end
		end
	end)
	Hub.Conns[#Hub.Conns + 1] = conn
else
	log("ไม่พบ ShopRemotes.Push — กด 🔁 หลังมีลูกค้า", C_RED)
end

function Hub.Stop()
	Hub.Running = false
	saveRating()
	for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
	Hub.Conns = {}
	pcall(function() gui:Destroy() end)
	getgenv().TwoK = nil
end

-- --------------------------------- boot ---------------------------------
loadRating()
layout()
task.defer(layout)
renderItems()

log("v31 พร้อม • ระบบประเมินแท้/เก๊ + ตัวกรองซ่อน + ระดับพระถูกต้อง", C_BLUE)
do
	local per, tot = {}, 0
	for id in next, Models do
		local t, th = tierOf(id)
		per[th] = (per[th] or 0) + 1
		tot = tot + 1
	end
	local parts = {}
	for _, k in ipairs(TIERS) do
		parts[#parts + 1] = (TIER_TH[k] or k) .. "=" .. tostring(per[TIER_TH[k] or k] or 0)
	end
	log(("อ่านระดับได้ %d พิมพ์: %s"):format(tot, table.concat(parts, " • ")), C_BLUE)
	local t = {}
	for _, k in ipairs(TIERS) do
		if Hub.Flags.Tiers[k] then t[#t + 1] = TIER_TH[k] end
	end
	log("รับเฉพาะ: " .. (#t > 0 and table.concat(t, " / ") or "ไม่รับเลย"), C_BLUE)
	log(("ผลประเมินที่โหลดมา: %d พิมพ์ • %d ลาย • %d โหวต")
		:format(countKeys(Rating.models), countKeys(Rating.sigs), Rating.total),
		Color3.fromRGB(190, 235, 190))
end

-- บันทึกผลประเมินอัตโนมัติทุก 6 วิ (เมื่อมีการเปลี่ยนแปลง)
task.spawn(function()
	while Hub.Running do
		task.wait(6)
		if RATE_DIRTY then saveRating() end
	end
end)