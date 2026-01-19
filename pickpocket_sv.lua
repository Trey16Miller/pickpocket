AddCSLuaFile()
AddCSLuaFile("pickpocket/sh_config.lua")
AddCSLuaFile("autorun/client/pickpocket_cl.lua")

include("pickpocket/sh_config.lua")

util.AddNetworkString("PP_Data")
util.AddNetworkString("PP_Action")
util.AddNetworkString("PP_Notify")
util.AddNetworkString("PP_Awareness")

local money = {}
local cd = {}
local aware = {}
local npcMoney = {}
local alerted = {}

local function Now() return CurTime() end

local function GetMoney(ply)
    return money[ply] or 0
end

local function SetMoney(ply, amt)
    amt = math.max(0, math.floor(tonumber(amt) or 0))
    money[ply] = amt
    ply:SetNWInt("PP_Money", amt)
end

hook.Add("PlayerInitialSpawn", "PP_LoadMoney", function(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        local saved = tonumber(ply:GetPData("pp_money", "0")) or 0
        SetMoney(ply, saved)
    end)
end)

hook.Add("PlayerDisconnected", "PP_SaveMoney", function(ply)
    if not IsValid(ply) then return end
    ply:SetPData("pp_money", tostring(GetMoney(ply)))
    money[ply] = nil
    cd[ply] = nil
end)

local function Notify(ply, msg)
    net.Start("PP_Notify")
        net.WriteString(msg or "")
    net.Send(ply)
end

local function KeyCooldown(ply)
    cd[ply] = cd[ply] or { next = 0 }
    return cd[ply]
end

local function IsSneaking(ply)
    if not IsValid(ply) then return false end
    if PICKPOCKET.RequireCrouch and not ply:Crouching() then return false end
    return true
end

local function InRange(ply, npc)
    return ply:GetPos():DistToSqr(npc:GetPos()) <= (PICKPOCKET.Range * PICKPOCKET.Range)
end

local function FacingDot(ply, npc)
    local toP = (ply:GetPos() - npc:GetPos()):GetNormalized()
    return npc:GetForward():Dot(toP)
end

local function IsBehindNPC(ply, npc)
    return FacingDot(ply, npc) < -0.35
end

local function IsInFrontOfNPC(ply, npc)
    return FacingDot(ply, npc) > 0.35
end

local function EnsureNPCMoney(npc)
    local id = npc:EntIndex()
    if npcMoney[id] == nil then
        npcMoney[id] = math.random(PICKPOCKET.MoneyMin, PICKPOCKET.MoneyMax)
    end
    return npcMoney[id] or 0
end

local function GetNPCAwareness(npc)
    return aware[npc:EntIndex()] or 0
end

local function SetNPCAwareness(npc, v)
    aware[npc:EntIndex()] = math.Clamp(v, 0, PICKPOCKET.AwarenessMax)
end

local function AddNPCAwareness(npc, dv)
    SetNPCAwareness(npc, GetNPCAwareness(npc) + dv)
end

local function ClearNPC(ent)
    local id = ent:EntIndex()
    aware[id] = nil
    npcMoney[id] = nil
    alerted[id] = nil
end

hook.Add("EntityRemoved", "PP_ClearNPC", function(ent)
    if IsValid(ent) and ent:IsNPC() then
        ClearNPC(ent)
    end
end)

local function SendAwarenessTo(ply, npc)
    if not IsValid(ply) or not IsValid(npc) then return end
    net.Start("PP_Awareness")
        net.WriteEntity(npc)
        net.WriteUInt(math.floor(GetNPCAwareness(npc)), 8)
    net.Send(ply)
end

timer.Create("PP_AwarenessThink", PICKPOCKET.TickRate, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end

        local sneaking = IsSneaking(ply)

        local near = ents.FindInSphere(ply:GetPos(), 240)
        for _, npc in ipairs(near) do
            if not IsValid(npc) or not npc:IsNPC() then continue end

            if not InRange(ply, npc) then
                AddNPCAwareness(npc, -PICKPOCKET.AwarenessDecay * PICKPOCKET.TickRate)
                SendAwarenessTo(ply, npc)
                continue
            end

            local front = IsInFrontOfNPC(ply, npc)
            local behind = IsBehindNPC(ply, npc)

            local gain = 0
            if behind and sneaking then
                gain = PICKPOCKET.AwarenessGainBehindSneak
            elseif front then
                if npc:Visible(ply) then
                    gain = PICKPOCKET.AwarenessGainFront
                else
                    gain = PICKPOCKET.AwarenessGainSide
                end
            else
                if npc:Visible(ply) then
                    gain = PICKPOCKET.AwarenessGainSide
                else
                    gain = 0
                end
            end

            AddNPCAwareness(npc, gain * PICKPOCKET.TickRate)
            SendAwarenessTo(ply, npc)
        end
    end
end)

timer.Create("PP_AlertThink", 0.2, 0, function()
    local now = CurTime()
    for npcId, info in pairs(alerted) do
        local npc = Entity(npcId)
        local ply = info.ply

        if not IsValid(npc) or not npc:IsNPC() or not IsValid(ply) or not ply:Alive() then
            alerted[npcId] = nil
            continue
        end

        if npc:Visible(ply) then
            info.lastPos = ply:GetPos()
            info.lastSeen = now
            continue
        end

        if now - (info.lastSeen or 0) >= PICKPOCKET.LoseSightTime then
            npc:SetEnemy(nil)
            npc:SetTarget(nil)

            local lastPos = info.lastPos or npc:GetPos()
            local ang = (lastPos - npc:GetPos()):Angle()
            npc:SetAngles(Angle(0, ang.y, 0))

            npc:SetSchedule(SCHED_ALERT_STAND)

            alerted[npcId] = nil
        end
    end
end)

local function CanOpenPickpocket(ply, npc)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    if not IsValid(npc) or not npc:IsNPC() then return false end
    if not InRange(ply, npc) then return false end
    if not IsSneaking(ply) then return false end
    if not IsBehindNPC(ply, npc) then return false end

    local c = KeyCooldown(ply)
    if Now() < (c.next or 0) then return false end
    if GetNPCAwareness(npc) >= PICKPOCKET.AwarenessMax then return false end

    return true
end

hook.Add("KeyPress", "PP_OpenOnUse", function(ply, key)
    if key ~= IN_USE then return end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * PICKPOCKET.Range,
        filter = ply,
        mask = MASK_SHOT
    })

    local npc = tr.Entity
    if not IsValid(npc) or not npc:IsNPC() then return end
    if not CanOpenPickpocket(ply, npc) then return end

    EnsureNPCMoney(npc)

    net.Start("PP_Data")
        net.WriteEntity(npc)
        net.WriteUInt(math.floor(EnsureNPCMoney(npc)), 16)
        local wep = npc:GetActiveWeapon()
        local hasWep = IsValid(wep)
        net.WriteBool(hasWep)
        net.WriteString(hasWep and wep:GetClass() or "")
    net.Send(ply)
end)

local function Fail(ply, npc, msg)
    local c = KeyCooldown(ply)
    c.next = Now() + PICKPOCKET.FailCooldown

    if IsValid(npc) then
        SetNPCAwareness(npc, PICKPOCKET.AwarenessMax)

        npc:SetEnemy(ply)
        npc:UpdateEnemyMemory(ply, ply:GetPos())
        npc:SetSchedule(SCHED_CHASE_ENEMY)

        alerted[npc:EntIndex()] = {
            ply = ply,
            lastPos = ply:GetPos(),
            lastSeen = CurTime()
        }
    end

    Notify(ply, msg or "You were caught!")
end

local function SuccessCD(ply)
    local c = KeyCooldown(ply)
    c.next = Now() + PICKPOCKET.SuccessCooldown
end

net.Receive("PP_Action", function(_, ply)
    if not IsValid(ply) then return end
    local npc = net.ReadEntity()
    local action = net.ReadString()

    if not IsValid(npc) or not npc:IsNPC() then return end
    if not InRange(ply, npc) then return end

    if GetNPCAwareness(npc) >= PICKPOCKET.AwarenessMax then
        Fail(ply, npc, "Too late — they noticed you.")
        return
    end

    if not IsSneaking(ply) or not IsBehindNPC(ply, npc) then
        Fail(ply, npc, "You must be crouching behind them.")
        return
    end

    if action == "money" then
        local amt = EnsureNPCMoney(npc)
        if amt <= 0 then
            Notify(ply, "No money left.")
            SuccessCD(ply)
            return
        end
        npcMoney[npc:EntIndex()] = 0
        SetMoney(ply, GetMoney(ply) + amt)
        Notify(ply, "Stole $" .. amt)
        SuccessCD(ply)
        return
    end

    if action == "gun" then
        local wep = npc:GetActiveWeapon()
        if not IsValid(wep) then
            Notify(ply, "No weapon to steal.")
            SuccessCD(ply)
            return
        end

        local class = wep:GetClass()
        wep:Remove()

        ply:Give(class)
        ply:SelectWeapon(class)

        Notify(ply, "Stole weapon: " .. class)
        SuccessCD(ply)
        return
    end
end)
