include("pickpocket/sh_config.lua")

local awareness = {}
local frame

net.Receive("PP_Notify", function()
    local msg = net.ReadString()
    if msg and msg ~= "" then
        chat.AddText(Color(255, 220, 120), "[Pickpocket] ", color_white, msg)
        surface.PlaySound("buttons/button15.wav")
    end
end)

net.Receive("PP_Data", function()
    local npc = net.ReadEntity()
    if not IsValid(npc) then return end

    local npcMoney = net.ReadUInt(16)
    local npcHasGun = net.ReadBool()
    local npcGunClass = net.ReadString() or ""

    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetTitle("Pickpocket")
    frame:SetSize(340, 210)
    frame:Center()
    frame:MakePopup()

    local m = vgui.Create("DLabel", frame)
    m:SetPos(16, 44)
    m:SetSize(310, 24)
    m:SetFont("Trebuchet24")
    m:SetText("Money: $" .. npcMoney)

    local g = vgui.Create("DLabel", frame)
    g:SetPos(16, 74)
    g:SetSize(310, 20)
    g:SetFont("Trebuchet18")
    g:SetText(npcHasGun and ("Weapon: " .. npcGunClass) or "Weapon: None")

    local stealMoney = vgui.Create("DButton", frame)
    stealMoney:SetPos(16, 110)
    stealMoney:SetSize(308, 34)
    stealMoney:SetText("Steal Money")

    stealMoney.DoClick = function()
        if not IsValid(npc) then return end
        net.Start("PP_Action")
            net.WriteEntity(npc)
            net.WriteString("money")
        net.SendToServer()
        frame:Close()
    end

    local stealGun = vgui.Create("DButton", frame)
    stealGun:SetPos(16, 150)
    stealGun:SetSize(308, 34)
    stealGun:SetText("Steal Weapon")
    stealGun:SetEnabled(npcHasGun)

    stealGun.DoClick = function()
        if not IsValid(npc) then return end
        net.Start("PP_Action")
            net.WriteEntity(npc)
            net.WriteString("gun")
        net.SendToServer()
        frame:Close()
    end
end)

net.Receive("PP_Awareness", function()
    local npc = net.ReadEntity()
    local val = net.ReadUInt(8)
    if IsValid(npc) then
        awareness[npc:EntIndex()] = val
    end
end)

hook.Add("HUDPaint", "PP_AwarenessHUD_TopRight", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 180,
        filter = ply,
        mask = MASK_SHOT
    })

    local npc = tr.Entity
    if not IsValid(npc) or not npc:IsNPC() then return end

    local val = awareness[npc:EntIndex()] or 0

    local w, h = 240, 56
    local x = ScrW() - w - 20
    local y = 20

    draw.RoundedBox(8, x, y, w, h, Color(0, 0, 0, 170))
    draw.SimpleText("Awareness: " .. val .. "%", "Trebuchet18", x + 10, y + 6, color_white)

    local barX, barY = x + 10, y + 28
    local barW, barH = w - 20, 12

    draw.RoundedBox(4, barX, barY, barW, barH, Color(255, 255, 255, 40))
    draw.RoundedBox(
        4,
        barX,
        barY,
        math.floor(barW * (val / 100)),
        barH,
        Color(255, 255, 255, 180)
    )

    draw.SimpleText(
        "Crouch behind + E",
        "Trebuchet18",
        x + 10,
        y + h - 4,
        Color(200, 200, 200),
        TEXT_ALIGN_LEFT,
        TEXT_ALIGN_BOTTOM
    )
end)
