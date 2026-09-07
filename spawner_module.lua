local Opt
if _G.__CW_SPAWN_CLEAN then pcall(_G.__CW_SPAWN_CLEAN) end
local cloneref = cloneref or clonereference or function(x) return x end
local RS = cloneref(game:GetService("ReplicatedStorage"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local Workspace = cloneref(game:GetService("Workspace"))
local TeleportService = cloneref(game:GetService("TeleportService"))
local CollectionService = cloneref(game:GetService("CollectionService"))
local lp = Players.LocalPlayer
local function reqmod(inst) if not inst then return nil end local ok, m = pcall(require, inst); if ok then return m end return nil end
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local ClientF = RS:WaitForChild("Client", 10)
local DataF = RS:WaitForChild("Data", 10)
local SharedF = RS:WaitForChild("Shared", 10)
local SharedMods = child(SharedF, "Modules")
local SharedUtil = child(SharedF, "Util")
local SharedEggs = child(SharedF, "Eggs")
local Assets = reqmod(child(DataF, "Assets"))
local PlotState = reqmod(child(ClientF, "PlotState"))
local AssetRoster = reqmod(child(ClientF, "AssetRoster"))
local AssetEarnings = reqmod(child(SharedUtil, "AssetEarnings"))
local SaveMod = reqmod(child(SharedF, "Save"))
local EggState = reqmod(child(ClientF, "EggState"))
local EggToolDisplay = reqmod(child(SharedEggs, "EggToolDisplay"))
local EggRenderer = reqmod(child(SharedEggs, "EggRenderer"))
local PlacedEggRenderer = reqmod(child(SharedEggs, "PlacedEggRenderer"))
local AssetRigFactory = reqmod(child(SharedMods, "AssetRigFactory"))
local AssetToolRig = reqmod(child(SharedMods, "AssetToolRig"))
local AssetInfoBillboard = reqmod(child(SharedMods, "AssetInfoBillboard"))
local Spatial = reqmod(child(child(SharedF, "Utils"), "Spatial"))
local ModelBounds = Spatial and Spatial.ModelBounds
local IncomePopup = reqmod(child(child(child(lp, "PlayerScripts"), "GUI"), "ActiveAssetIncomePopup"))
local Bases = reqmod(child(DataF, "Bases"))
local AssetItems = reqmod(child(SharedUtil, "AssetItems"))
local Remotes = reqmod(child(SharedF, "Remotes"))
local AssetPalette = reqmod(child(SharedUtil, "AssetPalette"))
local Trails = reqmod(child(DataF, "Trails"))
local FuseKernel = reqmod(child(SharedUtil, "FuseKernel"))
local Treadmills = reqmod(child(DataF, "Treadmills"))
local Gears = reqmod(child(DataF, "Gears"))
local GearToolLookup = reqmod(child(SharedUtil, "GearToolLookup"))
local ToolGameplayGuard = reqmod(child(ClientF, "ToolGameplayGuard"))
local Mutations = reqmod(child(SharedMods, "Mutations"))
assert(Assets, "Assets module missing")
assert(AssetRoster, "AssetRoster missing")
local RUNNING = true
local CONNS = {}
local FAKE_ROSTER = {}
local FAKE_INV = {}
local FAKE_EGG = {}
local LS_ORIG = {}
local HELD_EGG_UID
local FAKE_EGG_CUE = {}
local FAKE_SKIP_CHOSEN
local FREE_SKIP = false
local injecting = false
local function track(c) if c then CONNS[#CONNS + 1] = c end return c end
local MUT_SCALAR = { Silver = 1.2, Golden = 2.5, Rainbow = 3.5, Sakura = 1.25, GreatBloom = 2.5 }
local function serverNow() local ok, t = pcall(function() return Workspace:GetServerTimeNow() end) return ok and t or os.time() end
local function copyRec(r)
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    if type(r.Mutations) == "table" then c.Mutations = table.clone(r.Mutations) end
    if type(r.Placement) == "table" then c.Placement = table.clone(r.Placement) end
    return c
end
local function dir(cat) return Assets.Directory and Assets.Directory[cat] end
local PET_LABEL_TO_KEY = {}
local function categoryList()
    table.clear(PET_LABEL_TO_KEY)
    local out = {}
    if Assets.Directory then
        for name, entry in pairs(Assets.Directory) do
            if type(name) == "string" and type(entry) == "table" and (entry.Rarity or entry._id) then
                local label = (type(entry.DisplayName) == "string" and entry.DisplayName ~= "") and entry.DisplayName or name
                if PET_LABEL_TO_KEY[label] and PET_LABEL_TO_KEY[label] ~= name then label = label .. " [" .. name .. "]" end
                PET_LABEL_TO_KEY[label] = name
                out[#out + 1] = label
            end
        end
    end
    table.sort(out)
    return out
end
local MUT_FALLBACK = { "Silver", "Golden", "Rainbow", "Monstrous", "Sakura", "GreatBloom" }
local function mutationList()
    local out = {}
    if Mutations and Mutations.All then
        local ok, cat = pcall(Mutations.All)
        if ok and type(cat) == "table" then
            for id, entry in pairs(cat) do if type(id) == "string" and type(entry) == "table" then out[#out + 1] = id end end
        end
    end
    if #out == 0 then for _, m in ipairs(MUT_FALLBACK) do out[#out + 1] = m end end
    table.sort(out)
    return out
end
local function rarityOf(cat) local e = dir(cat); local r = e and e.Rarity return r and (r.DisplayName or r._id) or "?" end
local function weightOf(cat, scale) local e = dir(cat); local mw = e and tonumber(e.ModelWeight) or 1 return mw * (math.max(scale, 0) ^ 3) end
local function scalePayout(s) if s <= 5 then return s ^ 1.85 end return (s / 5) ^ 1.2 * 19.637875755794113 end
local function mutMult(muts) local sum = 1 for _, m in ipairs(muts or {}) do local sc = MUT_SCALAR[m] if sc then sum = sum + math.max(0, sc - 1) end end return math.max(1, sum) end
local function saveProfile()
    if not SaveMod then return nil end
    local ok, s = pcall(function()
        if SaveMod.Cache and SaveMod.IsLocalDataLoaded and SaveMod.IsLocalDataLoaded() then return SaveMod.Cache()[lp] end
        return SaveMod.Get and SaveMod.Get()
    end)
    return ok and s or nil
end
local function earnRate(cat, scale, muts, item)
    if AssetEarnings and AssetEarnings.LiveRatePerSecond and item then
        local prof = saveProfile()
        local ok, r = pcall(AssetEarnings.LiveRatePerSecond, item, prof and prof.Gamepasses, prof and prof.Products)
        if ok and type(r) == "number" then return r end
    end
    local e = dir(cat); local base = e and tonumber(e.EarningRate) or 0
    return math.max(math.round(base * scalePayout(scale) * mutMult(muts)), 1)
end
local function fmt(n)
    n = math.round(n)
    for _, u in ipairs({ { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if math.abs(n) >= u[1] then return string.format("%.1f%s", n / u[1], u[2]) end
    end
    return tostring(n)
end
local function pen()
    if PlotState and PlotState.ResolvePlot then
        local ok, plot = pcall(PlotState.ResolvePlot)
        if ok and type(plot) == "table" then
            local area = plot.PetArea
            if area and area:IsA("BasePart") then return area, plot end
            if plot.CenterPoint and plot.CenterPoint:IsA("BasePart") then return plot.CenterPoint, plot end
        end
    end
    return nil
end
local GROUND = child(child(child(Workspace, "__OBJECTS"), "Areas"), "Ground")
local function randPointInPen(area, rad)
    rad = rad or 2
    local hx = math.max(area.Size.X * 0.5 - rad - 1.75, 1)
    local hz = math.max(area.Size.Z * 0.5 - rad - 1.75, 1)
    return area.CFrame:PointToWorldSpace(Vector3.new((math.random() * 2 - 1) * hx, 0, (math.random() * 2 - 1) * hz))
end
local function groundY(x, z, area)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    local incl = { area }; if GROUND then incl[#incl + 1] = GROUND end
    rp.FilterDescendantsInstances = incl; rp.IgnoreWater = true
    local res = Workspace:Raycast(Vector3.new(x, area.Position.Y + 64, z), Vector3.new(0, -2000, 0), rp)
    return res and res.Position.Y or (area.Position.Y + area.Size.Y * 0.5)
end
local UIDN = 0
local function nextUid(tag) UIDN = UIDN + 1 return ("CWFAKE_%s_%d_%d"):format(tag, UIDN, math.random(1000, 9999)) end
local PersCat = (type(Assets) == "table") and Assets.Personalities or nil
local CW_PERS = "Auto"
local function weightedRollPersonality()
    local tbl = PersCat and PersCat.RollTable
    if type(tbl) == "table" then
        local total = 0
        for _, e in ipairs(tbl) do total = total + (tonumber(e.Weight) or 0) end
        if total > 0 then
            local r = math.random() * total
            for _, e in ipairs(tbl) do
                r = r - (tonumber(e.Weight) or 0)
                if r <= 0 and type(e.Personality) == "string" then return e.Personality end
            end
        end
    end
    return "Normal"
end
local function autoOwnedPersonality(cat)
    local prof = saveProfile()
    if type(prof) ~= "table" or type(prof.Inventory) ~= "table" then return nil end
    for uid, it in pairs(prof.Inventory) do
        if type(it) == "table" and it.Category == cat
           and type(it.Personality) == "string"
           and not (type(uid) == "string" and string.find(uid, "CWFAKE", 1, true)) then
            return it.Personality
        end
    end
    return nil
end
local function rollPersonality(cat)
    local mode = CW_PERS or "Auto"
    if mode == "Auto" then
        local p = cat and autoOwnedPersonality(cat)
        if type(p) == "string" then return p end
        return weightedRollPersonality()
    end
    if mode == "Roll" then return weightedRollPersonality() end
    return mode
end
local CW_COLOR = "Auto"
local CW_SKIN = "None"
local SHOP_SELL = false
local function weightedRollColorIndex(cat)
    local e = dir(cat)
    local pmc = e and e.PossibleModelColors
    if type(pmc) ~= "table" or #pmc == 0 then return 1 end
    local total = 0
    for _, slot in ipairs(pmc) do total = total + (tonumber(slot[2]) or 0) end
    if total <= 0 then return 1 end
    local r = math.random() * total
    for i, slot in ipairs(pmc) do
        r = r - (tonumber(slot[2]) or 0)
        if r <= 0 then return i end
    end
    return 1
end
local function mutSig(arr)
    if type(arr) ~= "table" then return "" end
    local t = {}
    for _, m in ipairs(arr) do if type(m) == "string" and m ~= "" then t[#t + 1] = m end end
    table.sort(t)
    return table.concat(t, "|")
end
local function autoOwnedColorIdentity(cat, muts)
    local prof = saveProfile()
    if not (prof and type(prof.Inventory) == "table") then return nil end
    local want = mutSig(muts)
    local fallback = nil
    for uid, raw in pairs(prof.Inventory) do
        if type(uid) == "string" and not string.find(uid, "CWFAKE", 1, true) and not FAKE_INV[uid] then
            local it = raw
            if AssetItems and AssetItems.Decode then local ok, d = pcall(AssetItems.Decode, raw); if ok and type(d) == "table" then it = d end end
            if type(it) == "table" and it.Category == cat then
                local idv = { EyeColor = it.EyeColor, ColorSeed = it.ColorSeed, ColorIndex = it.ColorIndex }
                if mutSig(it.Mutations) == want then return idv end
                fallback = fallback or idv
            end
        end
    end
    return fallback
end
local function rollEyeColor()
    if AssetPalette and AssetPalette.DrawEyeColorHex then
        local ok, hex = pcall(AssetPalette.DrawEyeColorHex, Random.new())
        if ok and type(hex) == "string" and hex ~= "" then return hex end
    end
    return "ffffff"
end
local function rollGender(cat)
    local e = dir(cat); local g = e and e.GenderLocked
    if g == "Male" or g == "Female" then return g end
    return (math.random() < 0.5) and "Male" or "Female"
end
local function colorFieldsFor(cat, muts)
    local mode = CW_COLOR or "Auto"
    if mode == "Auto" and cat then
        local id = autoOwnedColorIdentity(cat, muts)
        if id then
            local eye = (type(id.EyeColor) == "string") and id.EyeColor or ""
            return eye, id.ColorSeed, id.ColorIndex
        end
    end
    if mode ~= "Base" and AssetPalette and AssetPalette.DrawFields and cat then
        local ok, f = pcall(AssetPalette.DrawFields, cat, Random.new())
        if ok and type(f) == "table" and f.EyeColor then
            return f.EyeColor, f.ColorSeed, f.ColorIndex
        end
    end
    local ci = (mode == "Base") and 1 or weightedRollColorIndex(cat)
    return rollEyeColor(), math.random(1, 1000000), ci
end
local function makePetItem(cat, scale, muts)
    muts = muts or {}
    local eye, seed, ci = colorFieldsFor(cat, muts)
    return {
        Category = cat, Mutations = muts, BaseMutation = muts[1],
        Scale = scale, EyeColor = eye, ColorSeed = seed, ColorIndex = ci,
        Personality = rollPersonality(cat),
        Gender = rollGender(cat),
        IsFavorite = not SHOP_SELL,
        HasBeenFirstPlaced = true,
    }
end
local function petItemFromEgg(rec)
    return {
        Category = rec.AssetCategory, Mutations = rec.Mutations or {}, BaseMutation = rec.BaseMutation,
        Scale = rec.AssetScale, EyeColor = rec.AssetEyeColor, ColorSeed = rec.AssetColorSeed, ColorIndex = rec.AssetColorIndex,
        Personality = rec.Personality or rec.AssetPersonality or rollPersonality(rec.AssetCategory),
        Gender = rec.AssetGender or rollGender(rec.AssetCategory), IsFavorite = not SHOP_SELL, HasBeenFirstPlaced = true,
    }
end
local function seatFollow(model, getHandle, aliveFn)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false; d.CanQuery = false; d.Massless = true; d:SetAttribute("KillPartIgnore", true)
            d.Anchored = (d == model.PrimaryPart)
        end
    end
    local center, size
    if ModelBounds then local ok, c, s = pcall(ModelBounds, model); if ok and c and s then center, size = c, s end end
    if not center then local ok2, c, s = pcall(function() return model:GetBoundingBox() end); if ok2 then center, size = c, s end end
    local rel
    if center and size then rel = (center * CFrame.new(0, size.Y * -0.5, size.Z * 0.1)):ToObjectSpace(model:GetPivot()) end
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if (aliveFn and not aliveFn()) or not model.Parent or not model.PrimaryPart then return end
        local char = lp.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local handle = getHandle and getHandle()
        if rel and handle and handle:IsA("BasePart") and hrp and (handle.Position - hrp.Position).Magnitude < 25 then
            pcall(function() model:PivotTo(handle.CFrame * rel) end)
            return
        end
        local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
        local anchor = (hand and hand.Position) or (hrp and (hrp.CFrame * CFrame.new(1.2, 0.2, -1.5)).Position)
        if not anchor then return end
        local look = hrp and Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
        if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
        pcall(function() model:PivotTo(CFrame.lookAt(anchor, anchor + look.Unit) * CFrame.new(0, -0.5, -0.6)) end)
    end)
    return conn
end
local function playIdle(model, cat)
    if not (model and cat and Assets and Assets.Directory) then return end
    local entry = Assets.Directory[cat]
    local idle = entry and entry.Animations and entry.Animations.Idle
    if not idle then return end
    task.spawn(function()
        local animator
        for _ = 1, 40 do
            if not (model and model.Parent) then return end
            animator = model:FindFirstChildWhichIsA("Animator", true)
                or model:FindFirstChildWhichIsA("AnimationController", true)
            if animator then break end
            task.wait(0.05)
        end
        if not animator then return end
        local ok, playing = pcall(function() return animator:GetPlayingAnimationTracks() end)
        if ok and type(playing) == "table" then
            for _, tr in ipairs(playing) do
                local a = tr.Animation
                if a and (a == idle or (typeof(idle) == "Instance" and a.AnimationId == idle.AnimationId)) then
                    return
                end
            end
        end
        local okL, track = pcall(function() return animator:LoadAnimation(idle) end)
        if okL and track then
            track.Looped = true
            track.Priority = Enum.AnimationPriority.Idle
            pcall(function() track:Play(0.1) end)
        end
    end)
end
local FAKE_PET_TOOL = {}
local function removePetTool(uid) local t = FAKE_PET_TOOL[uid] if t then pcall(function() t:Destroy() end) FAKE_PET_TOOL[uid] = nil end end
local function createPetTool(uid, item)
    removePetTool(uid)
    local bp = lp:FindFirstChild("Backpack"); if not bp or not item then return end
    if AssetToolRig and AssetToolRig.Build then
        local ok, tool = pcall(AssetToolRig.Build, item, uid, lp)
        if ok and typeof(tool) == "Instance" and tool:IsA("Tool") then
            FAKE_PET_TOOL[uid] = tool
            return
        end
    end
    local tool = Instance.new("Tool")
    tool.Name = item.Category or "Pet"
    tool.RequiresHandle = true; tool.CanBeDropped = false
    tool:SetAttribute("ItemType", "Asset")
    tool:SetAttribute("UID", uid)
    tool:SetAttribute("GuardTransparencyExcluded", true)
    pcall(function() CollectionService:AddTag(tool, "AssetTool") end)
    local handle = Instance.new("Part")
    handle.Name = "Handle"; handle.Size = Vector3.new(0.2, 0.2, 0.2); handle.Transparency = 1
    handle.CanCollide = false; handle.CanQuery = false; handle.CanTouch = false; handle.Massless = true
    handle.Parent = tool
    tool.Parent = bp
    FAKE_PET_TOOL[uid] = tool
    local heldModel
    local function clearHeld() if heldModel then pcall(function() heldModel:Destroy() end) heldModel = nil end end
    tool.Equipped:Connect(function()
        clearHeld()
        local h = tool:FindFirstChild("Handle"); if not (h and AssetRigFactory) then return end
        local ok, m
        if AssetRigFactory.BuildActive then ok, m = pcall(AssetRigFactory.BuildActive, uid, item, true, true)
        else ok, m = pcall(AssetRigFactory.Build, item, true) end
        if not (ok and m and m.PrimaryPart) then if m then pcall(function() m:Destroy() end) end return end
        local prim = m.PrimaryPart
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true; d:SetAttribute("KillPartIgnore", true) end
        end
        prim.Anchored = false
        local center, size = m:GetBoundingBox()
        if ModelBounds then local okb, c, s = pcall(ModelBounds, m); if okb and c and s then center, size = c, s end end
        pcall(function() m:PivotTo(h.CFrame * (center * CFrame.new(0, size.Y * -0.5, size.Z * 0.1)):ToObjectSpace(m:GetPivot())) end)
        local wc = Instance.new("WeldConstraint"); wc.Part0 = prim; wc.Part1 = h; wc.Parent = prim
        m.Name = "CWHeldPet"; m.Parent = tool
        playIdle(m, item.Category)
        if AssetInfoBillboard and AssetInfoBillboard.Attach then
            local okB, bb = pcall(AssetInfoBillboard.Attach, m, item.Category, item)
            if okB and typeof(bb) == "Instance" and bb:IsA("BillboardGui") then bb.MaxDistance = bb.MaxDistance * 2.8; bb.Enabled = true end
        end
        heldModel = m
    end)
    tool.Unequipped:Connect(clearHeld)
    tool.AncestryChanged:Connect(function() if not tool.Parent then clearHeld() end end)
end
local function mergedOwnerRecords()
    local out = {}
    local ok, real = pcall(AssetRoster.ReadOwnerPen, lp.UserId)
    if ok and type(real) == "table" then for uid, rec in pairs(real) do out[uid] = rec end end
    for uid, rec in pairs(FAKE_ROSTER) do out[uid] = rec end
    return out
end
local function refireRoster()
    if injecting then return end
    injecting = true
    pcall(function() AssetRoster.OwnerRefreshed:Fire(lp.UserId, mergedOwnerRecords()) end)
    injecting = false
end
local function watchRoster(sig)
    if sig then track(sig:Connect(function()
        if injecting or not RUNNING or next(FAKE_ROSTER) == nil then return end
        task.defer(refireRoster)
    end)) end
end
watchRoster(AssetRoster.OwnerRefreshed)
watchRoster(AssetRoster.SnapshotRefreshed)
local function setEquipped(uid, on)
    local prof = saveProfile(); if not prof then return end
    local eq = table.clone(prof.EquippedAssets or {})
    local idx = table.find(eq, uid)
    if on and not idx then table.insert(eq, uid)
    elseif not on and idx then table.remove(eq, idx) end
    if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedAssets", eq) end
end
local function putInInventory(uid, item)
    local prof = saveProfile(); if not prof then return end
    if type(prof.Inventory) == "table" then
        prof.Inventory[uid] = item; FAKE_INV[uid] = item
        pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
    end
end
local function rosterRecordFor(uid, item)
    local rate = earnRate(item.Category, item.Scale, item.Mutations, item)
    return { OwnerUserId = lp.UserId, UID = uid, ItemData = item, MoneyPerSecond = rate, Seed = math.random(1, 1000000), IsFirstPlacement = false }, rate
end
local function equipFakePet(uid)
    local item = FAKE_INV[uid]; if not item then return end
    local rec = rosterRecordFor(uid, item)
    FAKE_ROSTER[uid] = rec
    setEquipped(uid, true)
    removePetTool(uid)
    refireRoster()
end
local function unequipFakePet(uid)
    FAKE_ROSTER[uid] = nil
    setEquipped(uid, false)
    refireRoster()
    createPetTool(uid, FAKE_INV[uid])
end
local function unequipAllRealPets()
    local seen, reals = {}, {}
    local function isReal(u) return type(u) == "string" and not seen[u] and not FAKE_INV[u] and not FAKE_ROSTER[u] and not string.find(u, "CWFAKE", 1, true) end
    local prof = saveProfile()
    if prof and type(prof.EquippedAssets) == "table" then
        for _, u in ipairs(prof.EquippedAssets) do if isReal(u) then seen[u] = true; reals[#reals + 1] = u end end
    end
    local okp, pen = pcall(AssetRoster.ReadOwnerPen, lp.UserId)
    if okp and type(pen) == "table" then
        for u in pairs(pen) do if isReal(u) then seen[u] = true; reals[#reals + 1] = u end end
    end
    local doff = Remotes and Remotes.PenRoster and Remotes.PenRoster.AskDoff
    local n = 0
    for _, u in ipairs(reals) do
        local ok = pcall(function() return AssetRoster.DoffAsset(u) end)
        if not ok and doff then ok = pcall(function() return doff:InvokeServer(u) end) end
        if ok then n = n + 1; pcall(setEquipped, u, false) end
        task.wait(0.05)
    end
    return true, n
end
local RESPECT_CAP = true
local function activeCapacity()
    local prof = saveProfile()
    if Bases and Bases.GetAssetEquipCapacity then
        local ok, c = pcall(Bases.GetAssetEquipCapacity, prof and prof.BaseUpgradeLevel)
        if ok and type(c) == "number" then return c end
    end
    return math.huge
end
local function activeCount()
    local prof = saveProfile()
    if prof and type(prof.EquippedAssets) == "table" then return #prof.EquippedAssets end
    local n = 0 for _ in pairs(FAKE_ROSTER) do n = n + 1 end
    return n
end
local function getMoney() local prof = saveProfile() return prof and tonumber(prof.Money) or 0 end
local function setMoney(v)
    v = tonumber(v); if not v then return false, "not a number" end
    if v < 0 then v = 0 end
    local prof = saveProfile(); if not prof then return false, "no profile" end
    if SaveMod and SaveMod.ApplyLocalField then
        pcall(SaveMod.ApplyLocalField, "Money", v)
        return true, v
    end
    return false, "SaveMod.ApplyLocalField unavailable"
end
local function moneyGainFX(amount)
    amount = tonumber(amount); if not amount or amount <= 0 then return end
    local pr = Remotes and Remotes.PenRoster
    local ev = pr and pr.CoinsGathered and pr.CoinsGathered.OnClientEvent
    if not ev then return end
    local payload = { { amount = amount } }
    if firesignal then if pcall(firesignal, ev, payload) then return end end
    if getconnections then pcall(function() for _, c in ipairs(getconnections(ev)) do if c.Function then pcall(c.Function, payload) end end end) end
end
local INDEX_ON_SPAWN = true
local function indexDiscoverLocal(cat)
    if not (INDEX_ON_SPAWN and cat and SaveMod and SaveMod.ApplyLocalFieldEntry) then return end
    local prof = saveProfile()
    if prof and type(prof.Index) == "table" and prof.Index[cat] == true then return end
    pcall(SaveMod.ApplyLocalFieldEntry, "Index", cat, true)
end
local function spawnPet(cat, scale, muts)
    if not pen() then return nil, "no plot / PetArea (stand on your base)" end
    local uid = nextUid("pet")
    local item = makePetItem(cat, scale, muts)
    indexDiscoverLocal(cat)
    if RESPECT_CAP and activeCount() >= activeCapacity() then
        putInInventory(uid, item)
        createPetTool(uid, item)
        return uid, nil, "capped"
    end
    putInInventory(uid, item)
    local rec, rate = rosterRecordFor(uid, item)
    FAKE_ROSTER[uid] = rec
    setEquipped(uid, true)
    refireRoster()
    return uid, rate
end
local function giveInventoryPet(item)
    local uid = nextUid("pet")
    indexDiscoverLocal(type(item) == "table" and item.Category or nil)
    putInInventory(uid, item)
    createPetTool(uid, item)
    return uid
end
local function petModel(uid)
    local folder = child(Workspace, "ClientRenderedAssets")
    return folder and folder:FindFirstChild(("%d_%s"):format(lp.UserId, uid))
end
task.spawn(function()
    while RUNNING do
        for _ = 1, 10 do if not RUNNING then break end task.wait(0.1) end
        if not RUNNING then break end
        for uid, rec in pairs(FAKE_ROSTER) do
            local m = petModel(uid)
            if m and IncomePopup and IncomePopup.Show then pcall(IncomePopup.Show, m, rec.MoneyPerSecond, { alwaysOnTop = true }) end
        end
    end
end)
task.spawn(function()
    while RUNNING do
        for _ = 1, 10 do if not RUNNING then break end task.wait(0.1) end
        if not RUNNING then break end
        local sum = 0
        for _, r in pairs(FAKE_ROSTER) do sum += (tonumber(r.MoneyPerSecond) or 0) end
        if sum > 0 then
            local prof = saveProfile()
            if prof and SaveMod and SaveMod.ApplyLocalField then
                local cur = tonumber(prof.Money) or 0
                pcall(SaveMod.ApplyLocalField, "Money", cur + sum)
            end
            local ls = lp:FindFirstChild("leaderstats")
            if ls then
                for _, v in ipairs(ls:GetChildren()) do
                    if (v:IsA("NumberValue") or v:IsA("IntValue")) then
                        local n = string.lower(v.Name)
                        if string.find(n, "/s") or string.find(n, "sec") then
                            if LS_ORIG[v] == nil then LS_ORIG[v] = v.Value end
                            pcall(function() v.Value = sum end)
                        end
                    end
                end
            end
        end
    end
end)
task.spawn(function()
    while RUNNING do
        for _ = 1, 15 do if not RUNNING then break end task.wait(0.1) end
        if not RUNNING then break end
        local bp = lp:FindFirstChild("Backpack"); local char = lp.Character
        for uid, item in pairs(FAKE_INV) do
            if not FAKE_ROSTER[uid] then
                local t = FAKE_PET_TOOL[uid]
                local present = t and t.Parent and (t.Parent == bp or (char and t.Parent == char))
                if not present then createPetTool(uid, item) end
            end
        end
    end
end)
if SaveMod and SaveMod.FieldChanged then
    track(SaveMod.FieldChanged:Connect(function(field)
        if not RUNNING then return end
        if field ~= nil and field ~= "Inventory" and field ~= "EggInventory" and field ~= "EquippedAssets" then return end
        local prof = saveProfile(); if not prof then return end
        local dirty = false
        for uid, item in pairs(FAKE_INV) do if type(prof.Inventory) == "table" and prof.Inventory[uid] == nil then prof.Inventory[uid] = item; dirty = true end end
        if dirty then pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end) end
        if type(prof.EquippedAssets) == "table" then
            local present = {}
            for _, u in ipairs(prof.EquippedAssets) do present[u] = true end
            local eq, eqDirty = table.clone(prof.EquippedAssets), false
            for uid in pairs(FAKE_ROSTER) do if not present[uid] then eq[#eq + 1] = uid; eqDirty = true end end
            if eqDirty and SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedAssets", eq) end
        end
        local needEgg = false
        if type(prof.EggInventory) == "table" then
            for uid, rec in pairs(FAKE_EGG) do if not rec.Placement and uid ~= HELD_EGG_UID and prof.EggInventory[uid] == nil then needEgg = true break end end
        end
        if needEgg then
            local inv = table.clone(prof.EggInventory or {})
            for uid, rec in pairs(FAKE_EGG) do if not rec.Placement and uid ~= HELD_EGG_UID then inv[uid] = copyRec(rec) end end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv) end
        end
    end))
end
local function eggColors(cat, muts) local eye, seed, ci = colorFieldsFor(cat, muts) return { EyeColor = eye, ColorSeed = seed, ColorIndex = ci } end
local EGG_TIMER = true
local function placedFakeRecord(cat, scale, muts, localCF, col)
    local now = serverNow(); col = col or eggColors(cat, muts)
    local rec = {
        AssetCategory = cat, AssetScale = scale, AssetEyeColor = col.EyeColor,
        AssetColorSeed = col.ColorSeed, AssetColorIndex = col.ColorIndex,
        Mutations = muts or {}, BaseMutation = (muts or {})[1],
        AssetPersonality = rollPersonality(cat),
        AssetGender = rollGender(cat),
        GrowthSpeedMultiplier = 1,
        EggSkin = (CW_SKIN ~= "None") and CW_SKIN or nil,
    }
    if EGG_TIMER then
        rec.Placement = { LocalCFrame = localCF, PlacedAt = now }
    else
        rec.Placement = { LocalCFrame = localCF, PlacedAt = now - 100000, ReadyAt = now - 1, GrowthDuration = 1 }
    end
    return rec
end
local function backpackFakeRecord(cat, scale, muts, col)
    col = col or eggColors(cat, muts)
    return { AssetCategory = cat, AssetScale = scale, AssetEyeColor = col.EyeColor, AssetColorSeed = col.ColorSeed, AssetColorIndex = col.ColorIndex, Mutations = muts or {}, BaseMutation = (muts or {})[1], AssetPersonality = rollPersonality(cat), AssetGender = rollGender(cat), GrowthSpeedMultiplier = 1, EggSkin = (CW_SKIN ~= "None") and CW_SKIN or nil }
end
local function refreshEggs()
    if PlacedEggRenderer and PlacedEggRenderer.Refresh then pcall(PlacedEggRenderer.Refresh) end
    if EggState then
        pcall(function() EggState.OwnerRefreshed:Fire(lp.UserId, EggState.ReadOwnerEggs(lp.UserId)) end)
        pcall(function() EggState.SnapshotRefreshed:Fire(EggState.ReadOwnedEggs()) end)
    end
end
local function markEggReady(uid)
    local rec = FAKE_EGG[uid]; if not (rec and rec.Placement and rec.Placement.ReadyAt == nil) then return false end
    local now = serverNow()
    rec.Placement.ReadyAt = now
    rec.Placement.PlacedAt = now - (tonumber(rec.Placement.GrowthDuration) or 1)
    return true
end
local function installHook(tbl, name, make)
    if not tbl then return end
    local real = tbl[name]
    if type(real) ~= "function" then return end
    local orig = real
    local fn = make(function(...) return orig(...) end)
    if not pcall(function() tbl[name] = fn end) then
        if hookfunction then local ok, tramp = pcall(hookfunction, real, fn); if ok and tramp then orig = tramp end end
    end
end
installHook(EggState, "FetchEggRecord", function(pass)
    return function(uid) if FAKE_EGG[uid] then return nil end return pass(uid) end
end)
installHook(EggState, "ReadOwnedEgg", function(pass)
    return function(owner, uid) if owner == lp.UserId and FAKE_EGG[uid] and FAKE_EGG[uid].Placement then return copyRec(FAKE_EGG[uid]) end return pass(owner, uid) end
end)
installHook(EggState, "ReadOwnerEggs", function(pass)
    return function(owner)
        local r = pass(owner)
        if owner == lp.UserId then
            if type(r) ~= "table" then r = {} end
            for uid, rec in pairs(FAKE_EGG) do if rec.Placement then r[uid] = copyRec(rec) end end
        end
        return r
    end
end)
installHook(EggState, "ReadOwnedEggs", function(pass)
    return function()
        local rows = pass()
        if type(rows) ~= "table" then rows = {} end
        local mine
        for _, row in ipairs(rows) do if row.OwnerUserId == lp.UserId then mine = row break end end
        if not mine then mine = { OwnerUserId = lp.UserId, Records = {} } rows[#rows + 1] = mine end
        if type(mine.Records) ~= "table" then mine.Records = {} end
        for uid, rec in pairs(FAKE_EGG) do if rec.Placement then mine.Records[uid] = copyRec(rec) end end
        return rows
    end
end)
installHook(EggState, "BeginSkipGrowth", function(pass)
    return function(uid)
        if FAKE_EGG[uid] and FAKE_EGG[uid].Placement then
            if FREE_SKIP then
                FAKE_SKIP_CHOSEN = uid
                markEggReady(uid); refreshEggs()
                task.defer(function() if FAKE_SKIP_CHOSEN == uid then FAKE_SKIP_CHOSEN = nil end end)
                return false, nil, nil
            end
            local remaining = 0
            local ER = reqmod(child(SharedUtil, "EggRecords"))
            pcall(function() if ER and ER.GrowthSecondsRemaining then remaining = tonumber(ER.GrowthSecondsRemaining(FAKE_EGG[uid], serverNow(), 1)) or 0 end end)
            local prod = reqmod(child(DataF, "Products"))
            local pid
            pcall(function()
                if prod and prod.GetEggSkipGrowthProduct then
                    local c = prod.GetEggSkipGrowthProduct(math.max(remaining, 301))
                    if type(c) == "table" then pid = tonumber(c.ProductId) end
                end
            end)
            pid = pid or 3611606887
            _G.__CW_SKIP_PENDING = uid
            if _G.__CW_SHOPSELL and _G.__CW_SHOPSELL.captureBuyId then pcall(_G.__CW_SHOPSELL.captureBuyId, pid) end
            pcall(function()
                local s = Instance.new("Sound")
                s.SoundId = "rbxassetid://129627240635324"; s.PlaybackSpeed = 1.35; s.Volume = 0.6
                s.Parent = game:GetService("SoundService"); s:Play()
                game:GetService("Debris"):AddItem(s, 4)
            end)
            task.spawn(function() pcall(function() game:GetService("MarketplaceService"):PromptProductPurchase(lp, pid) end) end)
            return false, nil, nil
        end
        return pass(uid)
    end
end)
installHook(EggState, "ReadChosenSkipUid", function(pass)
    return function() if FAKE_SKIP_CHOSEN ~= nil then return FAKE_SKIP_CHOSEN end return pass() end
end)
installHook(EggState, "MayBuyChosenSkip", function(pass)
    return function()
        local uid = _G.__CW_SKIP_PENDING
        if uid and FAKE_EGG[uid] then return true end
        return pass()
    end
end)
installHook(EggState, "BeginHatch", function(pass)
    return function(uid) if FAKE_EGG[uid] then return true, nil end return pass(uid) end
end)
installHook(EggState, "FinishHatch", function(pass)
    return function(uid)
        if FAKE_EGG[uid] then
            local rec = FAKE_EGG[uid]
            FAKE_EGG[uid] = nil
            refreshEggs()
            local grant = giveInventoryPet(petItemFromEgg(rec))
            return true, nil, grant
        end
        return pass(uid)
    end
end)
local FAKE_TOOL, FAKE_HELD_MODEL, FAKE_HELD_CONN, FAKE_TOOL_KEEPER
local function destroyFakeTool()
    HELD_EGG_UID = nil
    if FAKE_TOOL_KEEPER then pcall(function() FAKE_TOOL_KEEPER:Disconnect() end) FAKE_TOOL_KEEPER = nil end
    if FAKE_HELD_CONN then pcall(function() FAKE_HELD_CONN:Disconnect() end) FAKE_HELD_CONN = nil end
    if FAKE_HELD_MODEL then pcall(function() FAKE_HELD_MODEL:Destroy() end) FAKE_HELD_MODEL = nil end
    if FAKE_TOOL then pcall(function() FAKE_TOOL:Destroy() end) FAKE_TOOL = nil end
end
local function newEggToolInstance(uid)
    local char = lp.Character; if not char then return nil end
    local tool = Instance.new("Tool")
    tool.Name = "Egg"; tool.RequiresHandle = true; tool.CanBeDropped = false
    tool:SetAttribute("GuardTransparencyExcluded", true)
    tool:SetAttribute("ItemType", "AssetEgg")
    tool:SetAttribute("UID", uid)
    pcall(function() CollectionService:AddTag(tool, "AssetTool") end)
    local handle = Instance.new("Part")
    handle.Name = "Handle"; handle.Size = Vector3.new(0.2, 0.2, 0.2); handle.Transparency = 1
    handle.CanCollide = false; handle.CanQuery = false; handle.CanTouch = false; handle.Anchored = false; handle.Massless = true
    handle.Parent = tool
    tool.Parent = char
    return tool
end
local function equipFakeEggTool(uid)
    destroyFakeTool()
    local rec = FAKE_EGG[uid]; if not rec or not lp.Character then return end
    HELD_EGG_UID = uid
    FAKE_TOOL = newEggToolInstance(uid)
    FAKE_TOOL_KEEPER = RunService.Heartbeat:Connect(function()
        if HELD_EGG_UID ~= uid then return end
        local c = lp.Character; if not c then return end
        if not FAKE_TOOL or FAKE_TOOL.Parent == nil then FAKE_TOOL = newEggToolInstance(uid)
        elseif FAKE_TOOL.Parent ~= c then pcall(function() FAKE_TOOL.Parent = c end) end
    end)
    track(FAKE_TOOL_KEEPER)
    task.defer(function()
        if HELD_EGG_UID ~= uid or not (EggRenderer and EggRenderer.RenderVisual) then return end
        local holder = child(Workspace, "CWHeld") or Instance.new("Folder")
        holder.Name = "CWHeld"; holder.Parent = Workspace
        local wrapper = { OwnerUserId = lp.UserId, UID = uid, ModelName = ("%d_%s"):format(lp.UserId, uid), Record = copyRec(rec), ScaleMultiplier = rec.AssetScale }
        local ok, res = pcall(EggRenderer.RenderVisual, wrapper, holder, false)
        if not ok or not res or not res.Model or not res.Model.PrimaryPart then return end
        FAKE_HELD_MODEL = res.Model
        FAKE_HELD_CONN = seatFollow(res.Model, function() return FAKE_TOOL and FAKE_TOOL:FindFirstChild("Handle") end, function() return HELD_EGG_UID == uid end)
        track(FAKE_HELD_CONN)
    end)
end
local function eggRenderFolder()
    if PlacedEggRenderer and PlacedEggRenderer.GetRenderFolder then
        local ok, f = pcall(PlacedEggRenderer.GetRenderFolder)
        if ok and typeof(f) == "Instance" then return f end
    end
    return child(Workspace, "PlacedEggRenders")
end
local function myEggFootprints()
    local out = {}
    local folder = eggRenderFolder(); if not folder then return out end
    local prefix = tostring(lp.UserId) .. "_"
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m.PrimaryPart and string.sub(m.Name, 1, #prefix) == prefix then
            local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
            if ok and cf and size then out[#out + 1] = { pos = cf.Position, r = math.max(size.X, size.Z) * 0.5 } end
        end
    end
    return out
end
local function newEggFootprintRadius(rec)
    if not (EggRenderer and EggRenderer.RenderVisual) then return 3 end
    local holder = Instance.new("Folder"); holder.Name = "CWMeasure"; holder.Parent = Workspace
    local r = 3
    local wrapper = { OwnerUserId = lp.UserId, UID = "CWmeasure", ModelName = "CWMEASURE", Record = copyRec(rec), ScaleMultiplier = rec.AssetScale }
    local ok, res = pcall(EggRenderer.RenderVisual, wrapper, holder, false)
    if ok and res and res.Model then
        local ok2, _, size = pcall(function() return res.Model:GetBoundingBox() end)
        if ok2 and size then r = math.max(size.X, size.Z) * 0.5 end
    end
    pcall(function() holder:Destroy() end)
    return r
end
local function placeFakeEggLocal(uid, localCF)
    local rec = FAKE_EGG[uid]; if not rec then return end
    local cat, scale, muts = rec.AssetCategory, rec.AssetScale, rec.Mutations or {}
    if not localCF then
        local area, plot = pen()
        if area and plot and plot.CenterPoint then
            local existing = myEggFootprints()
            local newR = newEggFootprintRadius(rec)
            local world
            for _ = 1, 40 do
                local p = randPointInPen(area, 2)
                local pos = Vector3.new(p.X, groundY(p.X, p.Z, area), p.Z)
                local okSpot = true
                for _, e in ipairs(existing) do
                    local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(e.pos.X, 0, e.pos.Z)).Magnitude
                    if d < (newR + e.r) then okSpot = false break end
                end
                if okSpot then world = CFrame.new(pos); break end
            end
            if not world then local p = randPointInPen(area, 2); world = CFrame.new(p.X, groundY(p.X, p.Z, area), p.Z) end
            localCF = plot.CenterPoint.CFrame:ToObjectSpace(world)
        else
            localCF = CFrame.new()
        end
    end
    FAKE_EGG[uid] = placedFakeRecord(cat, scale, muts, localCF, { EyeColor = rec.AssetEyeColor, ColorSeed = rec.AssetColorSeed, ColorIndex = rec.AssetColorIndex })
    local prof = saveProfile()
    if prof and type(prof.EggInventory) == "table" and prof.EggInventory[uid] ~= nil then
        local inv = table.clone(prof.EggInventory); inv[uid] = nil
        if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv) end
    end
    destroyFakeTool()
    FAKE_EGG_CUE[uid] = true
    refreshEggs()
end
installHook(EggState, "WearEggTool", function(pass)
    return function(uid) if FAKE_EGG[uid] and not FAKE_EGG[uid].Placement then task.spawn(equipFakeEggTool, uid) return true, nil end return pass(uid) end
end)
installHook(EggState, "DoffEggTool", function(pass)
    return function(uid) if FAKE_EGG[uid] then destroyFakeTool() return true, nil end return pass(uid) end
end)
installHook(EggState, "PlantEgg", function(pass)
    return function(uid, localCF)
        if FAKE_EGG[uid] then task.spawn(function() placeFakeEggLocal(uid, typeof(localCF) == "CFrame" and localCF or nil) end) return true, nil end
        return pass(uid, localCF)
    end
end)
installHook(EggState, "TakePlantCue", function(pass)
    return function(uid)
        if FAKE_EGG_CUE[uid] then FAKE_EGG_CUE[uid] = nil return true end
        return pass(uid)
    end
end)
installHook(AssetRoster, "DoffAsset", function(pass)
    return function(uid) if FAKE_INV[uid] then unequipFakePet(uid) return true, nil end return pass(uid) end
end)
installHook(AssetRoster, "WearAsset", function(pass)
    return function(uid) if FAKE_INV[uid] then equipFakePet(uid) return true, nil, nil end return pass(uid) end
end)
local function isFakeUid(uid) return type(uid) == "string" and (FAKE_INV[uid] ~= nil or string.find(uid, "CWFAKE", 1, true) ~= nil) end
local function sellOneFakeLocal(uid)
    local item = FAKE_INV[uid]; if not item then return 0 end
    local price = 0
    if AssetItems and AssetItems.SalePrice then local ok, p = pcall(AssetItems.SalePrice, item); if ok and tonumber(p) then price = p end end
    if lp:GetAttribute("VIP") then price = price * 2 end
    FAKE_INV[uid] = nil; FAKE_ROSTER[uid] = nil
    removePetTool(uid)
    local prof = saveProfile()
    if prof then
        if type(prof.Inventory) == "table" then prof.Inventory[uid] = nil; if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end end
        if type(prof.EquippedAssets) == "table" then
            local eq = {}
            for _, u in ipairs(prof.EquippedAssets) do if u ~= uid then eq[#eq + 1] = u end end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedAssets", eq) end
        end
        pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
    end
    if price > 0 then setMoney(getMoney() + price); moneyGainFX(price) end
    refireRoster()
    return price
end
local function applyShopSellFlag()
    for _, item in pairs(FAKE_INV) do if type(item) == "table" then item.IsFavorite = not SHOP_SELL end end
    local prof = saveProfile()
    if prof and type(prof.Inventory) == "table" then
        if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end
        pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
    end
end
local function setFakeFav(uid, fav)
    fav = fav and true or false
    if type(FAKE_INV[uid]) == "table" then
        FAKE_INV[uid].IsFavorite = fav
        local prof = saveProfile()
        if prof and type(prof.Inventory) == "table" and prof.Inventory[uid] then prof.Inventory[uid].IsFavorite = fav
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end
            pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
        end
    elseif type(FAKE_EGG[uid]) == "table" then
        FAKE_EGG[uid].IsFavorite = fav
        local prof = saveProfile()
        if prof and type(prof.EggInventory) == "table" and prof.EggInventory[uid] then prof.EggInventory[uid].IsFavorite = fav
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", prof.EggInventory) end
        end
    end
end
local function sellFakeEggLocal(uid)
    if not FAKE_EGG[uid] then return false end
    FAKE_EGG[uid] = nil
    local prof = saveProfile()
    if prof and type(prof.EggInventory) == "table" and prof.EggInventory[uid] then
        local inv = table.clone(prof.EggInventory); inv[uid] = nil
        if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv) end
    end
    return true
end
local function splitSellList(list)
    if type(list) ~= "table" then return nil, 0 end
    local reals, fakes = {}, 0
    for _, uid in ipairs(list) do
        if isFakeUid(uid) then pcall(sellOneFakeLocal, uid); fakes = fakes + 1
        else reals[#reals + 1] = uid end
    end
    return reals, fakes
end
if hookmetamethod and getnamecallmethod and Remotes then
    _G.__CW_SHOPSELL = {
        sell = splitSellList, isFake = isFakeUid,
        sellPet = Remotes.PetSatchel and Remotes.PetSatchel.SellPet,
        sellEvery = Remotes.PetSatchel and Remotes.PetSatchel.SellEveryPet,
        sellSelection = Remotes.PetSatchel and Remotes.PetSatchel.SellSelection,
        writeFav = Remotes.PetSatchel and Remotes.PetSatchel.WriteFavourite,
        setFav = setFakeFav, sellEgg = sellFakeEggLocal,
        fuseLoad = Remotes.Fusery and Remotes.Fusery.LoadPet,
        fuseEjectRF = Remotes.Fusery and Remotes.Fusery.EjectPet,
        fuseBeginRF = Remotes.Fusery and Remotes.Fusery.BeginFuse,
        fuseFinishRF = Remotes.Fusery and Remotes.Fusery.FinishReveal,
        treadRaise = Remotes.Treadmill and Remotes.Treadmill.AskTierRaise,
        wearBat = Remotes.Codex and Remotes.Codex.AskWearFieldBat,
    }
    if not _G.__CW_NC_HOOK then
        _G.__CW_NC_HOOK = true
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local S = _G.__CW_SHOPSELL
            if S then
                local m = getnamecallmethod()
                if m == "FireServer" and (self == S.sellPet or self == S.sellEvery) then
                    local reals, fakes = S.sell((...))
                    if fakes and fakes > 0 then
                        if reals and #reals > 0 then return oldNamecall(self, reals) end
                        return
                    end
                elseif m == "FireServer" and S.sellSelection and self == S.sellSelection then
                    local payload = (...)
                    if type(payload) == "table" then
                        local realA, fakeA = S.sell(payload.Assets)
                        local realE, fakeE = {}, 0
                        if type(payload.Eggs) == "table" then
                            for _, uid in ipairs(payload.Eggs) do
                                if type(uid) == "string" and (FAKE_EGG[uid] ~= nil or string.find(uid, "CWFAKE", 1, true)) then fakeE = fakeE + 1; if S.sellEgg then pcall(S.sellEgg, uid) end
                                else realE[#realE + 1] = uid end
                            end
                        end
                        if (fakeA and fakeA > 0) or fakeE > 0 then
                            if (realA and #realA > 0) or #realE > 0 then return oldNamecall(self, { Assets = realA or {}, Eggs = realE }) end
                            return
                        end
                    end
                elseif m == "FireServer" and S.writeFav and self == S.writeFav then
                    local uid, fav = ...
                    if type(uid) == "string" and (S.isFake(uid) or FAKE_EGG[uid] ~= nil) then
                        if S.setFav then pcall(S.setFav, uid, fav) end
                        return
                    end
                elseif m == "InvokeServer" and self == S.fuseLoad then
                    local r = S.fuseLoadPet and S.fuseLoadPet((...))
                    if r ~= nil then return r end
                elseif m == "InvokeServer" and S.fuseEjectRF and self == S.fuseEjectRF then
                    local r = S.fuseEject and S.fuseEject((...))
                    if r ~= nil then return r end
                elseif m == "InvokeServer" and S.fuseBeginRF and self == S.fuseBeginRF then
                    if S.fuseBegin then
                        local egg, err = S.fuseBegin()
                        if egg then return true, nil, egg end
                        if err then return false, err end
                    end
                elseif m == "InvokeServer" and S.fuseFinishRF and self == S.fuseFinishRF then
                    if S.fuseFinish and S.fuseFinish() then return true end
                elseif m == "InvokeServer" and S.treadRaise and self == S.treadRaise then
                    if S.upgradeTread then local ok = S.upgradeTread(); if ok then return true end return false, "not enough money" end
                elseif m == "InvokeServer" and S.trailBuy and self == S.trailBuy then
                    local id = (...)
                    if type(id) == "string" and S.buyTrail then
                        local ok, err = S.buyTrail(id)
                        if ok then return true end
                        return false, tostring(err)
                    end
                elseif m == "InvokeServer" and S.trailChoose and self == S.trailChoose then
                    local id = (...)
                    if type(id) == "string" and S.equipTrailLocal then S.equipTrailLocal(id); return true end
                elseif m == "InvokeServer" and S.wearBat and self == S.wearBat then
                    local section = (...)
                    if S.equipBatBySection and type(section) == "string" then
                        task.spawn(S.equipBatBySection, section)
                        return true
                    end
                    return false, "bat not recognized"
                elseif m == "InvokeServer" and S.redeemLimitedEgg and self == S.redeemLimitedEgg then
                    if S.grantGear then task.spawn(S.grantGear, "BeeLauncher"); return true end
                    return false, "reward unavailable"
                elseif m == "InvokeServer" and S.captureBuyId and (self == S.storeProbe or self == S.storeOffer) then
                    pcall(S.captureBuyId, (...))
                end
            end
            return oldNamecall(self, ...)
        end)
    end
end
installHook(FuseKernel, "MayEnterFuse", function(pass)
    return function(uid, item, selectedCat, wantInFuse)
        if isFakeUid(uid) then
            local inFuse = (type(item) == "table" and item.InFuse == true)
            if wantInFuse ~= inFuse then
                return false, wantInFuse and "That pet is not in this fuse machine" or "That pet is already in a fuse machine"
            end
            if selectedCat ~= nil and type(item) == "table" and item.Category ~= selectedCat then
                return false, "All three pets must be the same category"
            end
            return true
        end
        return pass(uid, item, selectedCat, wantInFuse)
    end
end)
local function unlockAllIndexVisual()
    local prof = saveProfile(); if not prof then return false, "no profile" end
    local idx, claimed = {}, {}
    if type(prof.Index) == "table" then for k, v in pairs(prof.Index) do idx[k] = v end end
    if type(prof.IndexClaimedCategories) == "table" then for k, v in pairs(prof.IndexClaimedCategories) do claimed[k] = v end end
    local n = 0
    if Assets.Directory then
        for cat, entry in pairs(Assets.Directory) do
            if type(cat) == "string" and type(entry) == "table" and (entry.Rarity or entry._id) then
                if not idx[cat] then n = n + 1 end
                idx[cat] = true
                claimed[cat] = true
            end
        end
    end
    if SaveMod.ApplyLocalField then
        pcall(SaveMod.ApplyLocalField, "Index", idx)
        pcall(SaveMod.ApplyLocalField, "IndexClaimedCategories", claimed)
    end
    return true, n
end
local TRAILS_DIR = (type(Trails) == "table" and type(Trails.Directory) == "table") and Trails.Directory or Trails
local TRAIL_LABEL_TO_ID = {}
local function trailLabels()
    table.clear(TRAIL_LABEL_TO_ID)
    local out = {}
    if type(TRAILS_DIR) == "table" then
        for id, t in pairs(TRAILS_DIR) do
            if type(id) == "string" and type(t) == "table" then
                local label = (type(t.DisplayName) == "string" and t.DisplayName ~= "") and t.DisplayName or id
                TRAIL_LABEL_TO_ID[label] = id; out[#out + 1] = label
            end
        end
    end
    table.sort(out)
    return out
end
local function trailPrice(id)
    local t = type(TRAILS_DIR) == "table" and TRAILS_DIR[id]
    return (t and tonumber(t.Price)) or 0
end
local function renderTrailNow(id)
    local re = Remotes and Remotes.Trailwear and Remotes.Trailwear.WornTrailShifted
    local sig = re and re.OnClientEvent
    if not sig then return end
    if type(firesignal) == "function" then pcall(firesignal, sig, lp, id); return end
    if type(getconnections) == "function" then
        local ok, conns = pcall(getconnections, sig)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do pcall(function() if c.Fire then c:Fire(lp, id) end end) end
        end
    end
end
local function equipTrailLocal(id)
    if not (id and TRAILS_DIR[id]) then return false end
    if SaveMod and SaveMod.ApplyLocalFieldEntry then pcall(SaveMod.ApplyLocalFieldEntry, "TrailInventory", id, true) end
    if SaveMod and SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedTrail", id) end
    renderTrailNow(id)
    return true
end
local function buyTrail(id)
    if not (id and type(TRAILS_DIR) == "table" and TRAILS_DIR[id]) then return false, "pick a trail" end
    local prof = saveProfile()
    local owned = prof and type(prof.TrailInventory) == "table" and prof.TrailInventory[id] == true
    if not owned then
        local price = trailPrice(id)
        if getMoney() < price then return false, ("need $%s"):format(fmt(price)) end
        if price > 0 then setMoney(getMoney() - price) end
    end
    equipTrailLocal(id)
    return true, id
end
local BAT_IDS = {}
local equipBat, equipBatBySection, unequipBat, grantGear
do
    local SECTION_BAT = {}
    do
        local Areas = reqmod(child(DataF, "Areas"))
        if Areas and Areas.Directory then
            for sectionId, area in pairs(Areas.Directory) do
                local gid = (type(area) == "table") and area.IndexBatGearId
                if type(gid) == "string" then SECTION_BAT[sectionId] = gid; BAT_IDS[#BAT_IDS + 1] = gid end
            end
        end
        if not next(SECTION_BAT) then
            local FB = { Forest = "Forest Bat", Lake = "Lake Bat", Desert = "Desert Bat", Jungle = "Jungle Bat", Snow = "Snow Bat", Volcano = "Volcano Bat", Cosmic = "Cosmic Bat", Prehistoric = "Prehistoric Bat", ["Abyss Ocean"] = "Abyss Ocean Bat", ["Cherry Blossom"] = "Katana" }
            for s, g in pairs(FB) do SECTION_BAT[s] = g; BAT_IDS[#BAT_IDS + 1] = g end
        end
        BAT_IDS[#BAT_IDS + 1] = "Bat"
    end
    local HIDDEN_BATS = {}
    local function isBatTool(t) return t:IsA("Tool") and (t:FindFirstChild("HitAnim") or t:FindFirstChild("IdleAnim")) end
    local function batAnimator()
        local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
        return hum and (hum:FindFirstChildOfClass("Animator") or hum) or nil
    end
    local function playBatAnim(animInst, looped, priority)
        if not animInst then return nil end
        local animator = batAnimator(); if not animator then return nil end
        local ok, tr = pcall(function() return animator:LoadAnimation(animInst) end)
        if not ok or not tr then return nil end
        pcall(function() tr.Priority = priority or Enum.AnimationPriority.Action; tr.Looped = looped and true or false; tr:Play() end)
        return tr
    end
    local function hideRealBats()
        local function scan(where)
            if not where then return end
            for _, t in ipairs(where:GetChildren()) do
                if isBatTool(t) and not t:GetAttribute("CWBAT") then
                    HIDDEN_BATS[#HIDDEN_BATS + 1] = { tool = t, parent = t.Parent }
                    pcall(function() t.Parent = nil end)
                end
            end
        end
        scan(lp:FindFirstChildOfClass("Backpack"))
        scan(lp.Character)
    end
    local function restoreRealBats()
        for _, e in ipairs(HIDDEN_BATS) do pcall(function() if e.tool and e.parent then e.tool.Parent = e.parent end end) end
        HIDDEN_BATS = {}
    end
    local function removeClonedBats()
        local function sweep(where) if where then for _, t in ipairs(where:GetChildren()) do if t:IsA("Tool") and t:GetAttribute("CWBAT") then t:Destroy() end end end end
        sweep(lp:FindFirstChildOfClass("Backpack"))
        sweep(lp.Character)
    end
    local function wireBatClone(tool)
        for _, s in ipairs(tool:GetDescendants()) do
            if s:IsA("LocalScript") or s:IsA("Script") then pcall(function() s:Destroy() end) end
        end
        pcall(function() tool:SetAttribute("IsBat", true) end)
        pcall(function() tool.Enabled = true end)
        local swingAnim = tool:FindFirstChild("HitAnim")
        if not swingAnim then for _, d in ipairs(tool:GetDescendants()) do if d:IsA("Animation") and d.Name ~= "IdleAnim" then swingAnim = d break end end end
        local hitTrack
        track(tool.Activated:Connect(function()
            local animator = batAnimator()
            if swingAnim and animator then
                if not hitTrack then local ok, tr = pcall(function() return animator:LoadAnimation(swingAnim) end); if ok then hitTrack = tr end end
                if hitTrack then pcall(function() hitTrack.Priority = Enum.AnimationPriority.Action; hitTrack:Stop(0); hitTrack:Play(0) end) end
            end
            pcall(function() tool.Enabled = true end)
            local handle = tool:FindFirstChild("Handle")
            if handle then
                local snd = handle:FindFirstChild("Slash") or handle:FindFirstChildWhichIsA("Sound")
                if snd and snd:IsA("Sound") then pcall(function() snd.TimePosition = 0; snd:Play() end) end
            end
        end))
    end
    local function setBatOwned(only)
        if not (SaveMod and SaveMod.ApplyLocalFieldEntry) then return end
        for _, id in ipairs(BAT_IDS) do
            pcall(SaveMod.ApplyLocalFieldEntry, "GearInventory", id, (id == only) and 1 or 0)
        end
    end
    function equipBat(gearId)
        if not gearId or gearId == "" then return false, "pick a bat" end
        setBatOwned(gearId)
        local entry = Gears and Gears.Directory and Gears.Directory[gearId]
        local toolModel = (type(entry) == "table" and type(entry.ToolModel) == "string" and entry.ToolModel) or gearId
        local tool = nil
        if type(GearToolLookup) == "function" then local ok, t = pcall(GearToolLookup, toolModel); if ok then tool = t end end
        if not tool then return true, gearId .. " (owned in index; no tool model to hold)" end
        removeClonedBats()
        restoreRealBats()
        hideRealBats()
        local clone = tool:Clone()
        clone:SetAttribute("CWBAT", true)
        wireBatClone(clone)
        local backpack = lp:FindFirstChildOfClass("Backpack")
        clone.Parent = backpack or lp.Character
        local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
        if hum and backpack and clone.Parent == backpack then pcall(function() hum:EquipTool(clone) end) end
        return true, gearId
    end
    function equipBatBySection(section)
        local g = section and SECTION_BAT[section]
        if not g then return false end
        return (equipBat(g))
    end
    function unequipBat()
        removeClonedBats()
        restoreRealBats()
        setBatOwned(nil)
        return true
    end
    function grantGear(gearId)
        if not gearId or gearId == "" then return false, "pick a gear" end
        if SaveMod and SaveMod.ApplyLocalFieldEntry then pcall(SaveMod.ApplyLocalFieldEntry, "GearInventory", gearId, 1) end
        local entry = Gears and Gears.Directory and Gears.Directory[gearId]
        local toolModel = (type(entry) == "table" and type(entry.ToolModel) == "string" and entry.ToolModel) or gearId
        local tool = nil
        if type(GearToolLookup) == "function" then local ok, t = pcall(GearToolLookup, toolModel); if ok then tool = t end end
        if not tool then return true, gearId .. " (owned; no tool to hold)" end
        removeClonedBats()
        local clone = tool:Clone()
        clone:SetAttribute("CWBAT", true)
        wireBatClone(clone)
        local backpack = lp:FindFirstChildOfClass("Backpack")
        clone.Parent = backpack or lp.Character
        local hum = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
        if hum and backpack and clone.Parent == backpack then pcall(function() hum:EquipTool(clone) end) end
        return true, gearId
    end
end
if _G.__CW_SHOPSELL then
    _G.__CW_SHOPSELL.equipBatBySection = equipBatBySection
    _G.__CW_SHOPSELL.grantGear = grantGear
    _G.__CW_SHOPSELL.redeemLimitedEgg = Remotes and Remotes.Codex and Remotes.Codex.AskRedeemLimitedEgg
end
if ToolGameplayGuard then
    installHook(ToolGameplayGuard, "AllowsLocalUse", function(pass)
        return function(tool)
            if tool and tool:GetAttribute("CWBAT") then return true end
            return pass(tool)
        end
    end)
end
if _G.__CW_SHOPSELL then
    _G.__CW_SHOPSELL.trailBuy = Remotes and Remotes.Trailwear and Remotes.Trailwear.AskPurchase
    _G.__CW_SHOPSELL.trailChoose = Remotes and Remotes.Trailwear and Remotes.Trailwear.AskChoose
    _G.__CW_SHOPSELL.buyTrail = buyTrail
    _G.__CW_SHOPSELL.equipTrailLocal = equipTrailLocal
end
local function treadmillNext()
    local prof = saveProfile()
    local cur = (prof and tonumber(prof.TreadmillUpgradeLevel)) or 0
    if not (Treadmills and Treadmills.GetByUpgradeLevel) then return nil end
    local ok, cfg = pcall(Treadmills.GetByUpgradeLevel, cur + 1)
    if ok and type(cfg) == "table" then return cur + 1, cfg end
    return nil
end
local function upgradeTreadmillLocal()
    local nextLvl, cfg = treadmillNext()
    if not nextLvl then return false, "max treadmill reached" end
    local price = tonumber(cfg.Price) or 0
    if getMoney() < price then return false, ("need $%s"):format(fmt(price)) end
    if price > 0 then setMoney(getMoney() - price) end
    if SaveMod and SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "TreadmillUpgradeLevel", nextLvl) end
    return true, nextLvl
end
if _G.__CW_SHOPSELL then _G.__CW_SHOPSELL.upgradeTread = upgradeTreadmillLocal end
local FUSE_PENDING
local function fuseSlots()
    local prof = saveProfile()
    if prof and type(prof.FusionSlots) == "table" then return prof.FusionSlots end
    return {}
end
local function fuseSetSlots(list)
    if SaveMod and SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "FusionSlots", list) end
end
local function fuseSetInFuse(uid, v)
    if type(FAKE_INV[uid]) == "table" then FAKE_INV[uid].InFuse = v or nil end
    local prof = saveProfile()
    if prof and type(prof.Inventory) == "table" and type(prof.Inventory[uid]) == "table" then prof.Inventory[uid].InFuse = v or nil end
end
local function fuseAllFake()
    local slots = fuseSlots()
    if #slots < 3 then return false end
    for _, u in ipairs(slots) do if not isFakeUid(u) then return false end end
    return true
end
local function fuseLoadPet(uid)
    if not isFakeUid(uid) then return nil end
    local slots = table.clone(fuseSlots())
    if #slots >= 3 then return true end
    for _, u in ipairs(slots) do if u == uid then return true end end
    slots[#slots + 1] = uid
    fuseSetInFuse(uid, true)
    fuseSetSlots(slots)
    return true
end
local function fuseEject(uid)
    if not isFakeUid(uid) then return nil end
    local out = {}
    for _, u in ipairs(fuseSlots()) do if u ~= uid then out[#out + 1] = u end end
    fuseSetInFuse(uid, false)
    fuseSetSlots(out)
    return true
end
local function fuseBegin()
    if not fuseAllFake() then return nil end
    local slots = fuseSlots()
    local first = FAKE_INV[slots[1]]
    local cat = (type(first) == "table" and first.Category) or "Dragon"
    local items, scales = {}, {}
    for _, u in ipairs(slots) do
        local it = FAKE_INV[u]
        items[#items + 1] = it
        scales[#scales + 1] = (type(it) == "table" and tonumber(it.Scale)) or 1
    end
    local scale
    if FuseKernel and FuseKernel.DrawFusedScale and #scales == 3 then
        local ok, s = pcall(FuseKernel.DrawFusedScale, scales, Random.new())
        if ok and tonumber(s) and s > 0 then scale = s end
    end
    if not scale then local a = 0; for _, s in ipairs(scales) do a = a + s end; scale = math.min((a / math.max(#scales, 1)) * 1.5, 100) end
    if FuseKernel and FuseKernel.PriceFor and #items == 3 then
        local ok, price = pcall(FuseKernel.PriceFor, items)
        if ok and tonumber(price) and price > 0 then
            if getMoney() < price then return false, "You don't have enough money to fuse!" end
            setMoney(getMoney() - price)
        end
    end
    local eye, seed, ci = colorFieldsFor(cat, {})
    local egg = {
        AssetCategory = cat, AssetScale = scale,
        AssetEyeColor = eye, AssetColorSeed = seed, AssetColorIndex = ci,
        Mutations = {}, AssetGender = rollGender(cat), AssetPersonality = rollPersonality(cat),
        GrowthSpeedMultiplier = 1,
    }
    FUSE_PENDING = egg
    return egg
end
local function resetFuseOverhead()
    pcall(function()
        local objs = workspace:FindFirstChild("__OBJECTS")
        local machines = objs and objs:FindFirstChild("Machines")
        local fm = machines and machines:FindFirstChild("FuseMachine")
        local overhead = fm and fm:FindFirstChild("Overhead")
        local bb = overhead and overhead:FindFirstChildWhichIsA("BillboardGui")
        local lbl = bb and bb:FindFirstChild("Countdown")
        if lbl and lbl:IsA("TextLabel") then lbl.Text = "0/3" end
    end)
end
local function fuseFinish()
    local egg = FUSE_PENDING; FUSE_PENDING = nil
    if not egg then return nil end
    local slots = fuseSlots()
    local prof = saveProfile()
    for _, uid in ipairs(slots) do
        FAKE_INV[uid] = nil; FAKE_ROSTER[uid] = nil
        removePetTool(uid)
        if prof and type(prof.Inventory) == "table" then prof.Inventory[uid] = nil end
    end
    if prof and type(prof.Inventory) == "table" and SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end
    fuseSetSlots({})
    if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "FusionLocked", false); pcall(SaveMod.ApplyLocalField, "FusionEggReward", false) end
    local uid = nextUid("egg")
    FAKE_EGG[uid] = {
        AssetCategory = egg.AssetCategory, AssetScale = egg.AssetScale,
        AssetEyeColor = egg.AssetEyeColor, AssetColorSeed = egg.AssetColorSeed, AssetColorIndex = egg.AssetColorIndex,
        Mutations = egg.Mutations or {}, BaseMutation = (egg.Mutations or {})[1],
        AssetPersonality = egg.AssetPersonality, AssetGender = egg.AssetGender,
        GrowthSpeedMultiplier = 1,
    }
    local inv = table.clone((prof and prof.EggInventory) or {})
    inv[uid] = copyRec(FAKE_EGG[uid])
    if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv) end
    refireRoster()
    refreshEggs()
    resetFuseOverhead()
    return true
end
if _G.__CW_SHOPSELL then
    _G.__CW_SHOPSELL.fuseLoadPet = fuseLoadPet
    _G.__CW_SHOPSELL.fuseEject = fuseEject
    _G.__CW_SHOPSELL.fuseBegin = fuseBegin
    _G.__CW_SHOPSELL.fuseFinish = fuseFinish
end
local function addBackpackEgg(cat, scale, muts)
    local prof = saveProfile(); if not prof then return false, "no profile" end
    local uid = nextUid("egg")
    FAKE_EGG[uid] = backpackFakeRecord(cat, scale, muts)
    local inv = table.clone(prof.EggInventory or {})
    inv[uid] = copyRec(FAKE_EGG[uid])
    if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv)
    else pcall(function() prof.EggInventory = inv; SaveMod.FieldSignal("EggInventory"):Fire(inv, inv) end) end
    return true, uid
end
local function placeEggDirect(cat, scale, muts)
    if not pen() then return false, "no plot / PetArea" end
    local uid = nextUid("egg")
    FAKE_EGG[uid] = backpackFakeRecord(cat, scale, muts)
    placeFakeEggLocal(uid, nil)
    return true, uid
end
local function clearAll()
    pcall(destroyFakeTool)
    for uid in pairs(FAKE_PET_TOOL) do removePetTool(uid) end
    local prof = saveProfile()
    local hadPlaced = false
    local eggUids = {}
    for uid, rec in pairs(FAKE_EGG) do if rec.Placement then hadPlaced = true end eggUids[#eggUids + 1] = uid end
    table.clear(FAKE_EGG)
    table.clear(FAKE_EGG_CUE)
    if prof and type(prof.EggInventory) == "table" and #eggUids > 0 then
        local inv = table.clone(prof.EggInventory)
        for _, uid in ipairs(eggUids) do inv[uid] = nil end
        if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EggInventory", inv) end
    end
    if hadPlaced then refreshEggs() end
    table.clear(FAKE_ROSTER)
    refireRoster()
    local petUids, isFake = {}, {}
    for uid in pairs(FAKE_INV) do petUids[#petUids + 1] = uid; isFake[uid] = true end
    table.clear(FAKE_INV)
    if prof then
        if type(prof.Inventory) == "table" then
            for _, uid in ipairs(petUids) do prof.Inventory[uid] = nil end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end
        end
        if type(prof.EquippedAssets) == "table" then
            local eq = {}
            for _, u in ipairs(prof.EquippedAssets) do if not isFake[u] then eq[#eq + 1] = u end end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedAssets", eq) end
        end
        pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
    end
    for inst, orig in pairs(LS_ORIG) do pcall(function() inst.Value = orig end) end
    table.clear(LS_ORIG)
end
local function sellFakePets()
    local n, sum = 0, 0
    for _, item in pairs(FAKE_INV) do
        n = n + 1
        if AssetItems and AssetItems.SalePrice and type(item) == "table" then
            local ok, p = pcall(AssetItems.SalePrice, item)
            if ok and tonumber(p) then sum = sum + (lp:GetAttribute("VIP") and p * 2 or p) end
        end
    end
    if n == 0 then return false, "no fake pets to sell (spawn some first)" end
    pcall(destroyFakeTool)
    for uid in pairs(FAKE_PET_TOOL) do removePetTool(uid) end
    table.clear(FAKE_ROSTER)
    refireRoster()
    local petUids, isFake = {}, {}
    for uid in pairs(FAKE_INV) do petUids[#petUids + 1] = uid; isFake[uid] = true end
    table.clear(FAKE_INV)
    local prof = saveProfile()
    if prof then
        if type(prof.Inventory) == "table" then
            for _, uid in ipairs(petUids) do prof.Inventory[uid] = nil end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "Inventory", prof.Inventory) end
        end
        if type(prof.EquippedAssets) == "table" then
            local eq = {}
            for _, u in ipairs(prof.EquippedAssets) do if not isFake[u] then eq[#eq + 1] = u end end
            if SaveMod.ApplyLocalField then pcall(SaveMod.ApplyLocalField, "EquippedAssets", eq) end
        end
        pcall(function() SaveMod.FieldSignal("Inventory"):Fire(prof.Inventory, prof.Inventory) end)
    end
    if sum > 0 then setMoney(getMoney() + sum); moneyGainFX(sum) end
    return true, ("sold %d fake pets -> +$%s (local)"):format(n, fmt(sum))
end
local SHOP = { balance = 100000, dropOnBuy = true, instant = false, closeUntil = 0 }
;(function()
local ShopCoreGui   = cloneref(game:GetService("CoreGui"))
local MarketplaceSvc = cloneref(game:GetService("MarketplaceService"))
local StarterGuiSvc = cloneref(game:GetService("StarterGui"))
local SHOP_GLYPH = '<font family="rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json" weight="400">robux</font>'
local SHOP_SAVE = "robux_balance_spoof.txt"
local shop_lastId, shop_lastGp = nil, false
local shop_busy, shop_armed = false, {}
local shop_lastSpend = {}
local shop_lastGrant = {}
local ShopProducts = reqmod(child(DataF, "Products"))
local ShopLimitedEgg = reqmod(child(DataF, "LimitedEgg"))
pcall(function() if readfile and isfile and isfile(SHOP_SAVE) then local n=tonumber(readfile(SHOP_SAVE)) if n then SHOP.balance=n end end end)
local function shop_persist() pcall(function() if writefile then writefile(SHOP_SAVE, tostring(SHOP.balance)) end end) end
local function shop_comma(n) local s=tostring(math.floor(tonumber(n) or 0)) local o,c="",0 for i=#s,1,-1 do o=s:sub(i,i)..o c=c+1 if c%3==0 and i>1 then o=","..o end end return o end
local function shop_roots() local r={} pcall(function() if gethui then r[#r+1]=gethui() end end) r[#r+1]=ShopCoreGui return r end
local function shop_status(msg) if SHOP.onStatus then pcall(SHOP.onStatus, msg) end end
local function shop_cfg(id) if not ShopProducts then return nil end
    local ok, c = pcall(function() return ShopProducts.ByProductId and ShopProducts.ByProductId[id] end); if ok and c then return c end
    if ShopProducts.Directory then for _, cc in pairs(ShopProducts.Directory) do if type(cc) == "table" and cc.ProductId == id then return cc end end end
end
local function shop_rollEggCat()
    local dt = ShopLimitedEgg and ShopLimitedEgg.DropTable
    if type(dt) ~= "table" then return nil end
    local total = 0 for _, e in ipairs(dt) do total = total + (tonumber(e[2]) or 0) end
    if total <= 0 then return nil end
    local r = math.random() * total
    for _, e in ipairs(dt) do r = r - (tonumber(e[2]) or 0) if r <= 0 and dir(e[1]) then return e[1] end end
    for _, e in ipairs(dt) do if dir(e[1]) then return e[1] end end
end
local function shop_grantLocal(id)
    if shop_lastGrant[id] and os.clock() - shop_lastGrant[id] < 1.5 then return false end
    local cfg = shop_cfg(id)
    local name = tostring((cfg and cfg.DisplayName) or "")
    if name:match("^Money") then
        local amt = tonumber((name:gsub("Money_?", ""):gsub("%D", "")))
        if amt and amt > 0 then shop_lastGrant[id] = os.clock(); setMoney(getMoney() + amt); moneyGainFX(amt); shop_status("added $" .. shop_comma(amt) .. " (local)"); return true end
    end
    if id == 3611613592 or name == "Grow All Eggs" then
        shop_lastGrant[id] = os.clock()
        local n = 0 for uid, rec in pairs(FAKE_EGG) do if rec.Placement then pcall(markEggReady, uid); n = n + 1 end end
        pcall(refreshEggs); shop_status("grew " .. n .. " fake egg(s)"); return true
    end
    if cfg and cfg.EggSkipGrowthMaxRemainingSeconds ~= nil then
        local uid = _G.__CW_SKIP_PENDING or (EggState.ReadChosenSkipUid and EggState.ReadChosenSkipUid())
        if uid and FAKE_EGG[uid] then
            shop_lastGrant[id] = os.clock()
            FAKE_SKIP_CHOSEN = uid
            pcall(markEggReady, uid); pcall(refreshEggs)
            _G.__CW_SKIP_PENDING = nil
            task.defer(function() if FAKE_SKIP_CHOSEN == uid then FAKE_SKIP_CHOSEN = nil end end)
            shop_status("skipped growth (local)"); return true
        end
        return false
    end
    if cfg and cfg.EggSkipGrowthMaxRemainingSeconds == nil and name:lower():find("egg") and not name:lower():find("skip") then
        local qty = tonumber(name:match("[xX]%s*(%d+)")) or 1
        local scale = (Opt and Opt.sp_scale and Opt.sp_scale.Value) or 3
        local n = 0 for _ = 1, qty do local cat = shop_rollEggCat() if cat then local ok = pcall(addBackpackEgg, cat, scale, {}) if ok then n = n + 1 end end end
        if n > 0 then shop_lastGrant[id] = os.clock(); shop_status("added " .. n .. " egg(s) to backpack (local)"); return true end
    end
    return false
end
local function shop_findBalanceLabel()
    for _, root in ipairs(shop_roots()) do
        local ok, ds = pcall(function() return root:GetDescendants() end)
        if ok then for _, d in ipairs(ds) do
            if d:IsA("TextLabel") and d.Name == "RobuxPrice" then
                local okp, p = pcall(function() return d:GetFullName() end)
                if okp and p:find("ModalHeader", 1, true) and p:find("RightSide", 1, true) then return d end
            end
        end end
    end
end
local function shop_applyBalance()
    local lbl = shop_findBalanceLabel(); if not lbl then return false end
    local glyph = (lbl.Text or ""):match("^(.-</font>)") or SHOP_GLYPH
    local want = glyph .. " " .. shop_comma(SHOP.balance)
    if lbl.Text ~= want then pcall(function() lbl.Text = want end) end
    return true
end
local function shop_priceOf(id, it) local ok, info = pcall(function() return MarketplaceSvc:GetProductInfo(id, it) end) if ok and info then return tonumber(info.PriceInRobux) end end
local function shop_spend(amount, key)
    if not amount or amount <= 0 then return end
    local now = os.clock() if key and shop_lastSpend[key] and now - shop_lastSpend[key] < 1.5 then return end if key then shop_lastSpend[key] = now end
    SHOP.balance = math.max(0, SHOP.balance - amount) shop_persist() shop_applyBalance()
end
function SHOP.setBalance(n)
    n = tonumber((tostring(n):gsub("[^%d]", ""))) if not n then return false end
    SHOP.balance = n shop_persist()
    local ok = shop_applyBalance()
    shop_status(ok and ("Balance = " .. shop_comma(n)) or ("Saved (" .. shop_comma(n) .. "). Open a purchase to apply."))
    return true
end
function SHOP.getBalance() return SHOP.balance end
SHOP.spend = shop_spend
local function shop_fireFinished(id, gp)
    id = tonumber(id) if not id then return end
    local uid = lp.UserId
    local sig = gp and MarketplaceSvc.PromptGamePassPurchaseFinished or MarketplaceSvc.PromptProductPurchaseFinished
    local args = gp and { lp, id, true } or { uid, id, true }
    local meth = gp and "SignalPromptGamePassPurchaseFinished" or "SignalPromptProductPurchaseFinished"
    if MarketplaceSvc[meth] then if pcall(function() MarketplaceSvc[meth](MarketplaceSvc, table.unpack(args)) end) then return end end
    if firesignal then if pcall(firesignal, sig, table.unpack(args)) then return end end
    if getconnections then pcall(function() for _, c in ipairs(getconnections(sig)) do if c.Function then pcall(c.Function, table.unpack(args)) end end end) end
end
local function shop_fireSettled(id)
    pcall(function()
        local ev = Remotes.Storefront.PurchaseSettled.OnClientEvent
        local args = { lp.UserId, { ProductId = tonumber(id) } }
        if firesignal then pcall(firesignal, ev, table.unpack(args)) end
        if getconnections then for _, c in ipairs(getconnections(ev)) do if c.Function then pcall(c.Function, table.unpack(args)) end end end
    end)
end
local function shop_complete(id, gp)
    id = tonumber(id) if not id then return end
    shop_fireFinished(id, gp)
    if not gp then shop_fireSettled(id) end
    if SHOP.dropOnBuy then shop_spend(shop_priceOf(id, gp and Enum.InfoType.GamePass or Enum.InfoType.Product), (gp and "gp" or "p") .. id) end
    local granted = false
    if not gp then local ok, r = pcall(shop_grantLocal, id); granted = ok and r end
    if not granted then shop_status(("bought #%s%s"):format(tostring(id), gp and " (pass)" or "")) end
end
SHOP.complete = shop_complete
pcall(function()
    local PP = reqmod(child(child(ClientF, "Functions"), "PromptPurchase"))
    if PP and PP.Prompt then
        local orig = PP.Prompt
        SHOP.ppOrig = orig
        PP.Prompt = function(id, isProduct, ...)
            if not RUNNING then return orig(id, isProduct, ...) end
            shop_lastId, shop_lastGp = id, (isProduct == false)
            if SHOP.instant then task.defer(function() shop_complete(id, shop_lastGp) end) return end
            return orig(id, isProduct, ...)
        end
    end
end)
if _G.__CW_SHOPSELL then
    _G.__CW_SHOPSELL.storeProbe = Remotes.Storefront and Remotes.Storefront.AskServerProbe
    _G.__CW_SHOPSELL.storeOffer = Remotes.Storefront and Remotes.Storefront.AskPurchaseOffer
    _G.__CW_SHOPSELL.captureBuyId = function(id) if id ~= nil then shop_lastId, shop_lastGp = id, false end end
end
local function shop_nukeSheets(duration)
    local t0 = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if os.clock() - t0 >= duration or not RUNNING then if conn then conn:Disconnect() end return end
        for _, root in ipairs(shop_roots()) do
            local ok, ds = pcall(function() return root:GetDescendants() end)
            if ok then for _, d in ipairs(ds) do
                if d.Name == "SheetContainer" then pcall(function() d.Visible = false end)
                elseif d.Name == "Backdrop" then
                    pcall(function() d.BackgroundTransparency = 1 end)
                    pcall(function() d.ImageTransparency = 1 end)
                end
            end end
        end
    end)
    track(conn)
end
local function shop_buyIsLoaded()
    for _, root in ipairs(shop_roots()) do
        local ok, ds = pcall(function() return root:GetDescendants() end)
        if ok then for _, d in ipairs(ds) do
            if d:IsA("TextLabel") and d.Name == "Text" then
                local okp, p = pcall(function() return d:GetFullName() end)
                if okp and p:find("FoundationOverlay", 1, true) and p:find("%.Actions%.") then
                    local btn = d.Parent
                    local active = false pcall(function() active = btn.Active end)
                    local grad = true pcall(function() grad = btn:FindFirstChildOfClass("UIGradient") ~= nil end)
                    local bt = 1 pcall(function() bt = btn.BackgroundTransparency end)
                    return active and (not grad) and bt < 0.1
                end
            end
        end end
    end
    return true
end
local function shop_onBuy()
    if shop_busy or not RUNNING then return end
    if not shop_buyIsLoaded() then return end
    shop_busy = true
    if shop_lastId then
        shop_complete(shop_lastId, shop_lastGp)
        SHOP.closeUntil = os.clock() + 6
        shop_nukeSheets(4)
    else
        shop_status("Buy caught, but no item id yet - reopen the item.")
    end
    task.delay(0.6, function() shop_busy = false end)
end
local function shop_armBuyButtons()
    if SHOP.instant then return end
    for _, root in ipairs(shop_roots()) do
        local ok, ds = pcall(function() return root:GetDescendants() end)
        if ok then for _, d in ipairs(ds) do
            if d:IsA("TextLabel") and (d.Text == "Buy" or d.Name == "Text") then
                local okp, p = pcall(function() return d:GetFullName() end)
                if okp and p:find("FoundationOverlay", 1, true) and p:find("%.Actions%.") then
                    local n = d.Parent
                    for _ = 1, 4 do
                        if n and n:IsA("GuiObject") and not shop_armed[n] then
                            shop_armed[n] = true
                            local evs = n:IsA("GuiButton") and { "Activated", "MouseButton1Click", "MouseButton1Down", "InputBegan" } or { "InputBegan", "InputEnded" }
                            for _, en in ipairs(evs) do pcall(function()
                                if getconnections then for _, c in ipairs(getconnections(n[en])) do pcall(function() c:Disable() end) end end
                            end) end
                            pcall(function() if n:IsA("GuiButton") then track(n.Activated:Connect(shop_onBuy)) end end)
                            pcall(function() track(n.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then shop_onBuy() end end)) end)
                        end
                        n = n and n.Parent
                    end
                end
            end
        end end
    end
end
task.spawn(function() while RUNNING do pcall(shop_applyBalance) pcall(shop_armBuyButtons) task.wait(0.1) end end)
local function shop_lockBackdrop(d)
    local function z() pcall(function() d.BackgroundTransparency = 1 end) pcall(function() d.ImageTransparency = 1 end) end
    z()
    pcall(function() track(d:GetPropertyChangedSignal("BackgroundTransparency"):Connect(z)) end)
    pcall(function() track(d:GetPropertyChangedSignal("ImageTransparency"):Connect(z)) end)
end
for _, root in ipairs(shop_roots()) do
    pcall(function() track(root.DescendantAdded:Connect(function(d) if d.Name == "Backdrop" then shop_lockBackdrop(d) end end)) end)
    pcall(function() for _, d in ipairs(root:GetDescendants()) do if d.Name == "Backdrop" then shop_lockBackdrop(d) end end end)
end
track(RunService.Heartbeat:Connect(function()
    if not RUNNING or os.clock() >= SHOP.closeUntil then return end
    local fo = ShopCoreGui:FindFirstChild("FoundationOverlay")
    if fo then for _, d in ipairs(fo:GetDescendants()) do if d.Name == "SheetContainer" then pcall(function() d.Visible = false end) end end end
end))
getgenv().RobuxSpoof = { set = SHOP.setBalance, spend = shop_spend, complete = shop_complete, get = SHOP.getBalance }
end)()
_G.__CW_SPAWN_CLEAN = function()
    RUNNING = false
    if SHOP and SHOP.ppOrig then pcall(function() local PP = reqmod(child(child(ClientF, "Functions"), "PromptPurchase")) if PP then PP.Prompt = SHOP.ppOrig end end) end
    _G.__CW_SHOPSELL = nil
    _G.__CW_ISFAKE = nil
    pcall(clearAll)
    for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
end
local M = {}
M.categoryList=categoryList M.mutationList=mutationList M.reqmod=reqmod M.child=child M.dir=dir
M.rarityOf=rarityOf M.weightOf=weightOf M.earnRate=earnRate M.makePetItem=makePetItem M.fmt=fmt
M.spawnPet=spawnPet M.activeCount=activeCount M.activeCapacity=activeCapacity M.placeEggDirect=placeEggDirect
M.addBackpackEgg=addBackpackEgg M.setMoney=setMoney M.sellFakePets=sellFakePets M.applyShopSellFlag=applyShopSellFlag
M.unequipFakePet=unequipFakePet M.clearAll=clearAll M.unlockAllIndexVisual=unlockAllIndexVisual M.saveProfile=saveProfile
M.grantGear=grantGear M.unequipBat=unequipBat M.unequipAllRealPets=unequipAllRealPets M.track=track
M.DataF=DataF M.PET_LABEL_TO_KEY=PET_LABEL_TO_KEY M.FAKE_ROSTER=FAKE_ROSTER M.FAKE_INV=FAKE_INV
M.SaveMod=SaveMod M.Gears=Gears M.SHOP=SHOP M.lp=lp M.TeleportService=TeleportService
M.getEGG_TIMER=function() return EGG_TIMER end M.setEGG_TIMER=function(v) EGG_TIMER=v end
M.getFREE_SKIP=function() return FREE_SKIP end M.setFREE_SKIP=function(v) FREE_SKIP=v end
M.getSHOP_SELL=function() return SHOP_SELL end M.setSHOP_SELL=function(v) SHOP_SELL=v end
M.getINDEX_ON_SPAWN=function() return INDEX_ON_SPAWN end M.setINDEX_ON_SPAWN=function(v) INDEX_ON_SPAWN=v end
M.getCW_SKIN=function() return CW_SKIN end M.setCW_SKIN=function(v) CW_SKIN=v end
M.getCW_PERS=function() return CW_PERS end M.setCW_PERS=function(v) CW_PERS=v end
M.getCW_COLOR=function() return CW_COLOR end M.setCW_COLOR=function(v) CW_COLOR=v end
M.bindOpt=function(o) Opt=o end
return M
