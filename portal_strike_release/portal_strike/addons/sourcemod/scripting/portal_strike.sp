#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.5.0"

// Portal Gun Models
#define MODEL_PORTAL_VIEW   "models/weapons/v_portalgun.mdl"
#define MODEL_PORTAL_WORLD  "models/weapons/w_portalgun.mdl"

// Portal Entity Models
#define MODEL_PORTAL_BLUE   "models/portals/portal1.mdl"
#define MODEL_PORTAL_ORANGE "models/portals/portal2.mdl"

// Visual Sprites & Laser Tracers
#define SPRITE_PORTAL_GLOW  "materials/sprites/glow01.vmt"
#define SPRITE_PORTAL_HALO  "materials/sprites/halo.vmt"

// Sounds
#define SOUND_FIRE_BLUE     "weapons/portalgun/portalgun_shoot_blue1.wav"
#define SOUND_FIRE_ORANGE   "weapons/portalgun/portalgun_shoot_red1.wav"
#define SOUND_PORTAL_OPEN   "weapons/portalgun/portal_open1.wav"
#define SOUND_PORTAL_CLOSE  "weapons/portalgun/portal_close1.wav"
#define SOUND_PORTAL_ARM    "ambient/machines/portalgun_rotate1.wav"

#define TEAM_UNASSIGNED 0
#define TEAM_SPECTATOR  1
#define TEAM_T          2
#define TEAM_CT         3

// Global Cap: Maximum 4 active portals across the entire level with FIFO replacement
#define MAX_GLOBAL_PORTALS 4
// Team quota: Maximum 2 active portals per team (FIFO within team)
#define MAX_TEAM_PORTALS 2

enum struct PortalInfo
{
    int entity;
    int glowEntity;    // Attached team-colored glowing sprite
    int lightEntity;   // Attached dynamic light
    int cameraEntity;  // Dynamic point_camera for see-through projection
    int team;          // CS_TEAM_T or CS_TEAM_CT
    int owner;         // Client index
    int portalType;    // 0 = Blue/Primary, 1 = Orange/Secondary
    float pos[3];
    float angles[3];
    float forwardVec[3];
    float creationTime;
}

PortalInfo g_Portals[MAX_GLOBAL_PORTALS];
int g_PortalCount = 0;

// Model / Sprite Index Cache
int g_PortalViewModelIndex = -1;
int g_PortalWorldModelIndex = -1;
int g_GlowSpriteIndex = -1;
int g_HaloSpriteIndex = -1;

// Per-player toggle and state tracking
bool g_PortalModeActive[MAXPLAYERS + 1];
int g_SavedWeaponModelIndex[MAXPLAYERS + 1];
int g_LastActiveWeapon[MAXPLAYERS + 1];
float g_LastToggleTime[MAXPLAYERS + 1];
float g_LastTeleportTime[MAXPLAYERS + 1];
float g_LastFireTime[MAXPLAYERS + 1];

// Bot Tactical AI Evaluation Tracking
float g_NextBotPortalCheck[MAXPLAYERS + 1];
float g_NextBotCombatCheck[MAXPLAYERS + 1];

// Exclusive Single-Bearer Portal Gun Assignment per team
int g_TeamPortalBearer[4]; // CS_TEAM_T (2), CS_TEAM_CT (3)

// ConVars for Universal End-of-Round Killcam
ConVar g_CvarKillcam;
ConVar g_CvarKillcamDuration;

// Kill Record for End-of-Round Cinematic Replay
enum struct KillRecord
{
    int killer;
    int victim;
    char killerName[MAX_NAME_LENGTH];
    char victimName[MAX_NAME_LENGTH];
    float killerPos[3];
    float victimPos[3];
    float killerAng[3];
    char weapon[32];
    bool headshot;
    float timestamp;
    bool valid;
}

KillRecord g_LastKill;

// Universal End-of-Round Killcam tracking
bool g_KillcamActive = false;
int g_KillcamEntity = -1;
int g_KillcamTicks = 0;
float g_KillcamStartPos[3];
float g_KillcamEndPos[3];
float g_KillcamTargetPos[3];

public Plugin myinfo = 
{
    name = "Portal Strike - Tactical Portal AI & Physics Engine",
    author = "Antigravity",
    description = "Authentic Portal mechanics, Bot AI intelligence, projectile traversal & hit registration for CS:S",
    version = PLUGIN_VERSION,
    url = "https://github.com/portal_strike"
};

public void OnPluginStart()
{
    PrecachePortalAssets();

    g_CvarKillcam = CreateConVar("sm_portal_killcam", "1", "Enable cinematic universal end-of-round final killcam", FCVAR_NOTIFY);
    g_CvarKillcamDuration = CreateConVar("sm_portal_killcam_duration", "3.5", "Duration in seconds of the final killcam", FCVAR_NOTIFY, true, 1.0, true, 8.0);
    AutoExecConfig(true, "plugin.portal_strike");

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    // Dedicated toggle commands for players and keybinds
    RegConsoleCmd("sm_portal_toggle", Command_TogglePortalMode, "Toggle between Tactical Firearm and Portal Gun Mode");
    RegConsoleCmd("sm_portalgold", Command_TogglePortalMode, "Alias for Portal Gun Mode toggle");
    RegConsoleCmd("sm_portal", Command_FirePortalManual, "Fire portal manually by index");
    RegConsoleCmd("sm_portal_clear", Command_ClearPortals, "Clear all active portals on the level");

    // Continuous tick loop for physical player teleportation and projectile tracking
    CreateTimer(0.04, Timer_PortalPhysicsTick, _, TIMER_REPEAT);

    PrintToServer("[Portal Strike] Tactical AI & Physics Traversal Engine v%s loaded.", PLUGIN_VERSION);
}

public void OnMapStart()
{
    PrecachePortalAssets();
    ClearAllPortals();
    EndKillcam();
    g_LastKill.valid = false;
    g_TeamPortalBearer[CS_TEAM_T] = -1;
    g_TeamPortalBearer[CS_TEAM_CT] = -1;

    for (int i = 1; i <= MaxClients; i++)
    {
        g_PortalModeActive[i] = false;
        g_SavedWeaponModelIndex[i] = -1;
        g_LastActiveWeapon[i] = -1;
        g_LastToggleTime[i] = 0.0;
        g_LastTeleportTime[i] = 0.0;
        g_LastFireTime[i] = 0.0;
        g_NextBotPortalCheck[i] = 0.0;
        g_NextBotCombatCheck[i] = 0.0;
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_TraceAttack, Hook_PlayerTraceAttack);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_TraceAttack, Hook_PlayerTraceAttack);
    if (g_KillcamActive && g_KillcamEntity > 0 && IsValidEntity(g_KillcamEntity))
    {
        SetClientViewEntity(client, client);
    }
}

void PrecachePortalAssets()
{
    g_PortalViewModelIndex = PrecacheModel(MODEL_PORTAL_VIEW, true);
    g_PortalWorldModelIndex = PrecacheModel(MODEL_PORTAL_WORLD, true);

    PrecacheModel(MODEL_PORTAL_BLUE, true);
    PrecacheModel(MODEL_PORTAL_ORANGE, true);

    g_GlowSpriteIndex = PrecacheModel(SPRITE_PORTAL_GLOW, true);
    g_HaloSpriteIndex = PrecacheModel(SPRITE_PORTAL_HALO, true);

    // Precache portal shader materials to prevent missing texture fallbacks
    PrecacheGeneric("materials/models/portals/portalstaticoverlay_1.vmt", true);
    PrecacheGeneric("materials/models/portals/portalstaticoverlay_2.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_1_dynamicmesh.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_2_dynamicmesh.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_1_anims.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_2_anims.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_refract_1.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_refract_2.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_stencil_hole.vmt", true);
    PrecacheGeneric("materials/models/portals/portal_depthdoubler.vmt", true);

    PrecacheSound(SOUND_FIRE_BLUE, true);
    PrecacheSound(SOUND_FIRE_ORANGE, true);
    PrecacheSound(SOUND_PORTAL_OPEN, true);
    PrecacheSound(SOUND_PORTAL_CLOSE, true);
    PrecacheSound(SOUND_PORTAL_ARM, true);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    EndKillcam();
    g_LastKill.valid = false;
    ClearAllPortals();
    CreateTimer(0.5, Timer_AssignBearers);
}

public Action Timer_AssignBearers(Handle timer)
{
    AssignInitialPortalBearers();
    return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    ClearAllPortals();
    StartKillcam();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
    {
        return;
    }

    g_PortalModeActive[client] = false;
    g_SavedWeaponModelIndex[client] = -1;
    g_LastActiveWeapon[client] = -1;
    g_LastToggleTime[client] = 0.0;
    g_LastTeleportTime[client] = 0.0;
    g_LastFireTime[client] = 0.0;
    g_NextBotPortalCheck[client] = GetGameTime() + GetRandomFloat(3.0, 7.0);
    g_NextBotCombatCheck[client] = GetGameTime() + GetRandomFloat(1.0, 2.5);

    if (!IsFakeClient(client))
    {
        if (g_TeamPortalBearer[team] == client)
        {
            PrintHintText(client, "[PORTAL BEARER: APERTURE ASHPD READY]\nPress [F] or [T] to Toggle Portal Gun\nMOUSE1: Portal A | MOUSE2: Portal B\nSee-through cameras active!");
        }
        else
        {
            PrintHintText(client, "[PORTAL STRIKE: TACTICAL LOADOUT]\nYour team's portal bearer carries the Portal Gun.\nUniversal portals can be used by all players!");
        }
    }
}

public Action Command_TogglePortalMode(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    TogglePortalMode(client);
    return Plugin_Handled;
}

void TogglePortalMode(int client)
{
    float now = GetGameTime();
    if (now - g_LastToggleTime[client] < 0.25)
    {
        return; // Debounce rapid toggle spam
    }
    g_LastToggleTime[client] = now;

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
    {
        return;
    }

    // Single-Bearer Enforcement: Only the designated team portal bearer can toggle/fire the Portal Gun
    if (g_TeamPortalBearer[team] != client)
    {
        if (!IsFakeClient(client))
        {
            int bearer = g_TeamPortalBearer[team];
            char bearerName[MAX_NAME_LENGTH];
            if (bearer > 0 && IsClientInGame(bearer))
            {
                GetClientName(bearer, bearerName, sizeof(bearerName));
            }
            else
            {
                Format(bearerName, sizeof(bearerName), "Another Teammate");
            }
            PrintCenterText(client, "[PORTAL GUN UNAVAILABLE]\nTeam portal bearer is: %s", bearerName);
            PrintToChat(client, "[Portal Strike] Only the designated portal bearer (%s) can deploy portals.", bearerName);
        }
        return;
    }

    if (!g_PortalModeActive[client])
    {
        // Switch to Portal Gun Mode
        g_PortalModeActive[client] = true;
        ApplyPortalGunViewmodel(client);
        EmitSoundToClient(client, SOUND_PORTAL_ARM, SOUND_FROM_PLAYER, SNDCHAN_ITEM, SNDLEVEL_NORMAL);

        char primaryColor[16], secondaryColor[16];
        if (team == CS_TEAM_CT)
        {
            Format(primaryColor, sizeof(primaryColor), "Blue");
            Format(secondaryColor, sizeof(secondaryColor), "Cyan");
        }
        else
        {
            Format(primaryColor, sizeof(primaryColor), "Orange");
            Format(secondaryColor, sizeof(secondaryColor), "Yellow");
        }

        PrintCenterText(client, "[PORTAL GUN ACTIVE]\nMOUSE1: %s Portal | MOUSE2: %s Portal", primaryColor, secondaryColor);
    }
    else
    {
        // Instant Restoral back to Tactical Firearm Mode
        g_PortalModeActive[client] = false;
        RestoreOriginalViewmodel(client);
        EmitSoundToClient(client, SOUND_PORTAL_CLOSE, SOUND_FROM_PLAYER, SNDCHAN_ITEM, SNDLEVEL_NORMAL);

        PrintCenterText(client, "[TACTICAL FIREARMS ACTIVE]\nStandard CS:S Controls Restored");
    }
}

public Action Command_ClearPortals(int client, int args)
{
    ClearAllPortals();
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Portal Strike] All tactical portals cleared.");
    }
    return Plugin_Handled;
}

public Action Command_FirePortalManual(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    int pType = 0;
    if (args >= 1)
    {
        char arg1[8];
        GetCmdArg(1, arg1, sizeof(arg1));
        pType = StringToInt(arg1);
    }

    TryFirePortal(client, pType);
    return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
    {
        return Plugin_Continue;
    }

    float gameTime = GetGameTime();

    // 1. Human Controls & Dedicated Toggle:
    if (!IsFakeClient(client))
    {
        if (impulse == 100 || impulse == 201)
        {
            impulse = 0; // Intercept impulse
            TogglePortalMode(client);
        }

        if (g_PortalModeActive[client])
        {
            EnsurePortalGunViewmodel(client);

            // Exclusive Portal Firing in Portal Mode
            if (buttons & IN_ATTACK)
            {
                buttons &= ~IN_ATTACK; // Suppress firearm bullets
                TryFirePortal(client, 0); // Primary Portal
            }

            if (buttons & IN_ATTACK2)
            {
                buttons &= ~IN_ATTACK2; // Suppress secondary action
                TryFirePortal(client, 1); // Secondary Portal
            }
        }
    }
    else
    {
        // 2. Comprehensive AI Bot Portal Intelligence:
        // Bot frame tick evaluation: strategic placement, cross-map angles & projectile awareness
        if (gameTime >= g_NextBotPortalCheck[client])
        {
            g_NextBotPortalCheck[client] = gameTime + GetRandomFloat(5.0, 10.0);
            EvaluateBotTacticalPlacement(client, team);
        }

        if (gameTime >= g_NextBotCombatCheck[client])
        {
            g_NextBotCombatCheck[client] = gameTime + GetRandomFloat(1.5, 3.5);
            EvaluateBotCombatAndProjectiles(client, team);
        }
    }

    return Plugin_Continue;
}

void EvaluateBotTacticalPlacement(int client, int team)
{
    // Single-Bearer Enforcement: Only the designated bot bearer can place portals
    if (g_TeamPortalBearer[team] != client)
    {
        return;
    }

    float eyePos[3], eyeAng[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);

    // Bot tests forward wall for portal deployment
    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, Filter_WorldOnly);
    if (TR_DidHit(trace))
    {
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);
        float dist = GetVectorDistance(eyePos, hitPos);

        // Valid tactical range for flanking portal
        if (dist > 120.0 && dist < 1200.0)
        {
            bool hasPortalA = false;
            bool hasPortalB = false;
            for (int i = 0; i < g_PortalCount; i++)
            {
                if (g_Portals[i].team == team)
                {
                    if (g_Portals[i].portalType == 0) hasPortalA = true;
                    if (g_Portals[i].portalType == 1) hasPortalB = true;
                }
            }

            int pType = 0;
            if (!hasPortalA)
            {
                pType = 0; // Deploy Portal A
            }
            else if (!hasPortalB)
            {
                pType = 1; // Deploy Portal B to complete the pair!
            }
            else
            {
                pType = GetRandomInt(0, 1); // Dynamic relocation of one end of the link
            }

            TryFirePortal(client, pType);
        }
    }
    delete trace;
}

void EvaluateBotCombatAndProjectiles(int client, int team)
{
    // If team has a paired portal network, bot checks if aiming through nearby portal grants line-of-sight
    if (g_PortalCount < 2)
    {
        return;
    }

    float eyePos[3];
    GetClientEyePosition(client, eyePos);

    // Find nearest portal of ANY team (universal open-access network)
    int nearIdx = -1;
    float minDist = 700.0;
    for (int i = 0; i < g_PortalCount; i++)
    {
        float d = GetVectorDistance(eyePos, g_Portals[i].pos);
        if (d < minDist)
        {
            minDist = d;
            nearIdx = i;
        }
    }

    if (nearIdx != -1)
    {
        int partnerIdx = GetPartnerPortalIndex(nearIdx);
        if (partnerIdx != -1)
        {
            // Check if enemies exist near exit portal
            for (int enemy = 1; enemy <= MaxClients; enemy++)
            {
                if (IsClientInGame(enemy) && IsPlayerAlive(enemy) && GetClientTeam(enemy) != team)
                {
                    float enemyPos[3];
                    GetClientAbsOrigin(enemy, enemyPos);
                    if (GetVectorDistance(enemyPos, g_Portals[partnerIdx].pos) < 700.0)
                    {
                        // Aim bot toward entry portal for tactical cross-portal ambush
                        float aimAng[3], dir[3];
                        SubtractVectors(g_Portals[nearIdx].pos, eyePos, dir);
                        GetVectorAngles(dir, aimAng);
                        TeleportEntity(client, NULL_VECTOR, aimAng, NULL_VECTOR);
                        break;
                    }
                }
            }
        }
    }
}

void ApplyPortalGunViewmodel(int client)
{
    if (g_PortalViewModelIndex <= 0)
    {
        return;
    }

    int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (vm > 0 && IsValidEntity(vm))
    {
        int curModel = GetEntProp(vm, Prop_Send, "m_nModelIndex");
        if (curModel != g_PortalViewModelIndex)
        {
            g_SavedWeaponModelIndex[client] = curModel;
            SetEntProp(vm, Prop_Send, "m_nModelIndex", g_PortalViewModelIndex);
        }

        int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (activeWep > 0 && IsValidEntity(activeWep) && g_PortalWorldModelIndex > 0)
        {
            g_LastActiveWeapon[client] = activeWep;
            SetEntProp(activeWep, Prop_Send, "m_nModelIndex", g_PortalWorldModelIndex);
        }
    }
}

void EnsurePortalGunViewmodel(int client)
{
    if (g_PortalViewModelIndex <= 0)
    {
        return;
    }

    int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (vm > 0 && IsValidEntity(vm))
    {
        int curModel = GetEntProp(vm, Prop_Send, "m_nModelIndex");
        if (curModel != g_PortalViewModelIndex)
        {
            g_SavedWeaponModelIndex[client] = curModel;
            SetEntProp(vm, Prop_Send, "m_nModelIndex", g_PortalViewModelIndex);
        }
    }
}

void RestoreOriginalViewmodel(int client)
{
    int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (vm > 0 && IsValidEntity(vm))
    {
        if (g_SavedWeaponModelIndex[client] > 0)
        {
            SetEntProp(vm, Prop_Send, "m_nModelIndex", g_SavedWeaponModelIndex[client]);
            g_SavedWeaponModelIndex[client] = -1;
        }
    }

    int activeWep = g_LastActiveWeapon[client];
    if (activeWep > 0 && IsValidEntity(activeWep))
    {
        ChangeEdictState(activeWep, GetEntSendPropOffs(activeWep, "m_nModelIndex"));
        g_LastActiveWeapon[client] = -1;
    }
}

bool Filter_WorldOnly(int entity, int contentsMask, any data)
{
    if (entity > 0 && entity <= MaxClients)
    {
        return false;
    }
    char cls[64];
    if (GetEdictClassname(entity, cls, sizeof(cls)))
    {
        if (StrEqual(cls, "prop_physics_override") || StrEqual(cls, "portal_strike_portal"))
        {
            return false;
        }
    }
    return true;
}

void TryFirePortal(int client, int portalType)
{
    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
    {
        return;
    }

    // Single-Bearer Enforcement
    if (g_TeamPortalBearer[team] != client)
    {
        return;
    }

    float now = GetGameTime();
    if (!IsFakeClient(client))
    {
        if (now - g_LastFireTime[client] < 0.3)
        {
            return;
        }
        g_LastFireTime[client] = now;
    }

    float eyePos[3], eyeAng[3], forwardVec[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);
    GetAngleVectors(eyeAng, forwardVec, NULL_VECTOR, NULL_VECTOR);

    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, Filter_WorldOnly);
    if (!TR_DidHit(trace))
    {
        delete trace;
        return;
    }

    float hitPos[3], hitNormal[3];
    TR_GetEndPosition(hitPos, trace);
    TR_GetPlaneNormal(trace, hitNormal);
    delete trace;

    if (GetVectorDistance(eyePos, hitPos) < 64.0)
    {
        return;
    }

    // Authentic Portal Geometry:
    // Offset flush along surface normal by 3.0 units to prevent z-fighting or geometry clipping
    float portalPos[3];
    portalPos[0] = hitPos[0] + (hitNormal[0] * 3.0);
    portalPos[1] = hitPos[1] + (hitNormal[1] * 3.0);
    portalPos[2] = hitPos[2] + (hitNormal[2] * 3.0);

    float portalAng[3];
    if (FloatAbs(hitNormal[2]) > 0.8)
    {
        // Floor or Ceiling placement:
        // Lay oval mesh flush along surface normal, aligning oval orientation with player's facing yaw
        portalAng[0] = (hitNormal[2] > 0.0) ? -90.0 : 90.0;
        portalAng[1] = eyeAng[1];
        portalAng[2] = 0.0;
    }
    else
    {
        // Vertical or angled wall placement:
        // Align oval flush facing outward with upright vertical orientation (roll = 0.0)
        GetVectorAngles(hitNormal, portalAng);
        portalAng[2] = 0.0;
    }

    if (portalType == 0)
    {
        EmitSoundToAll(SOUND_FIRE_BLUE, client, SNDCHAN_WEAPON, SNDLEVEL_NORMAL);
    }
    else
    {
        EmitSoundToAll(SOUND_FIRE_ORANGE, client, SNDCHAN_WEAPON, SNDLEVEL_NORMAL);
    }

    // Independent Portal Slots (Portal A & Portal B):
    // portalType 0 = Portal A (Primary: Blue for CT, Orange for T)
    // portalType 1 = Portal B (Secondary: Cyan for CT, Yellow for T)
    // If a portal of this exact slot already exists for the team, remove/move it,
    // leaving the other slot completely untouched!
    int existingSlotIdx = -1;
    for (int i = 0; i < g_PortalCount; i++)
    {
        if (g_Portals[i].team == team && g_Portals[i].portalType == portalType)
        {
            existingSlotIdx = i;
            break;
        }
    }

    if (existingSlotIdx != -1)
    {
        RemovePortalAtIndex(existingSlotIdx);
    }
    else
    {
        // Enforce global level cap if at maximum 4 active portals
        if (g_PortalCount >= MAX_GLOBAL_PORTALS)
        {
            RemovePortalAtIndex(0);
        }
    }

    int glowEnt = -1;
    int lightEnt = -1;
    int camEnt = -1;
    int ent = CreatePortalEntity(portalPos, portalAng, team, portalType, hitNormal, glowEnt, lightEnt, camEnt);
    if (ent > 0)
    {
        EmitSoundToAll(SOUND_PORTAL_OPEN, ent, SNDCHAN_BODY, SNDLEVEL_NORMAL);

        g_Portals[g_PortalCount].entity = ent;
        g_Portals[g_PortalCount].glowEntity = glowEnt;
        g_Portals[g_PortalCount].lightEntity = lightEnt;
        g_Portals[g_PortalCount].cameraEntity = camEnt;
        g_Portals[g_PortalCount].team = team;
        g_Portals[g_PortalCount].owner = client;
        g_Portals[g_PortalCount].portalType = portalType;
        g_Portals[g_PortalCount].pos = portalPos;
        g_Portals[g_PortalCount].angles = portalAng;
        g_Portals[g_PortalCount].forwardVec = hitNormal;
        g_Portals[g_PortalCount].creationTime = GetGameTime();
        g_PortalCount++;

        // Live See-Through Portal Projection Linking:
        // Position each portal's point_camera at the partner's exit face, pointing out!
        int partnerIdx = GetPartnerPortalIndex(g_PortalCount - 1);
        if (partnerIdx != -1)
        {
            int myIdx = g_PortalCount - 1;
            int myCam = g_Portals[myIdx].cameraEntity;
            if (myCam > 0 && IsValidEntity(myCam))
            {
                float partnerCamPos[3];
                partnerCamPos[0] = g_Portals[partnerIdx].pos[0] + (g_Portals[partnerIdx].forwardVec[0] * 12.0);
                partnerCamPos[1] = g_Portals[partnerIdx].pos[1] + (g_Portals[partnerIdx].forwardVec[1] * 12.0);
                partnerCamPos[2] = g_Portals[partnerIdx].pos[2] + (g_Portals[partnerIdx].forwardVec[2] * 12.0);
                TeleportEntity(myCam, partnerCamPos, g_Portals[partnerIdx].angles, NULL_VECTOR);
                AcceptEntityInput(myCam, "SetOn");
            }

            int partnerCam = g_Portals[partnerIdx].cameraEntity;
            if (partnerCam > 0 && IsValidEntity(partnerCam))
            {
                float myCamPos[3];
                myCamPos[0] = g_Portals[myIdx].pos[0] + (g_Portals[myIdx].forwardVec[0] * 12.0);
                myCamPos[1] = g_Portals[myIdx].pos[1] + (g_Portals[myIdx].forwardVec[1] * 12.0);
                myCamPos[2] = g_Portals[myIdx].pos[2] + (g_Portals[myIdx].forwardVec[2] * 12.0);
                TeleportEntity(partnerCam, myCamPos, g_Portals[myIdx].angles, NULL_VECTOR);
                AcceptEntityInput(partnerCam, "SetOn");
            }
        }

        char slotName[16], colorName[16];
        if (team == CS_TEAM_CT)
        {
            Format(slotName, sizeof(slotName), portalType == 0 ? "Portal A" : "Portal B");
            Format(colorName, sizeof(colorName), portalType == 0 ? "Blue" : "Cyan");
        }
        else
        {
            Format(slotName, sizeof(slotName), portalType == 0 ? "Portal A" : "Portal B");
            Format(colorName, sizeof(colorName), portalType == 0 ? "Orange" : "Yellow");
        }

        // Check if paired link is now complete
        bool isLinked = (GetPartnerPortalIndex(g_PortalCount - 1) != -1);

        if (!IsFakeClient(client))
        {
            if (isLinked)
            {
                PrintCenterText(client, "[UNIVERSAL PORTAL LINK ACTIVE]\n%s (%s) connected! Open cross-team traversal ready.", slotName, colorName);
                PrintToChat(client, "[Portal Strike] %s (%s) linked! Universal traversal active for CT & T.", slotName, colorName);
            }
            else
            {
                PrintCenterText(client, "[%s DEPLOYED]\nFire %s to complete the link", slotName, portalType == 0 ? "Portal B" : "Portal A");
                PrintToChat(client, "[Portal Strike] %s (%s) placed. Fire %s to complete the linked pair.", 
                    slotName, colorName, portalType == 0 ? "Secondary [MOUSE2]" : "Primary [MOUSE1]");
            }
        }
    }
}

stock int GetTeamPortalCount(int team)
{
    int count = 0;
    for (int i = 0; i < g_PortalCount; i++)
    {
        if (g_Portals[i].team == team)
        {
            count++;
        }
    }
    return count;
}

int CreatePortalEntity(float pos[3], float ang[3], int team, int portalType, float hitNormal[3], int &outGlow, int &outLight, int &outCamera)
{
    if (portalType < 0) portalType = 0;
    int ent = CreateEntityByName("prop_physics_override");
    if (ent <= 0 || !IsValidEntity(ent))
    {
        return -1;
    }

    char model[PLATFORM_MAX_PATH];
    strcopy(model, sizeof(model), (team == CS_TEAM_CT) ? MODEL_PORTAL_BLUE : MODEL_PORTAL_ORANGE);
    SetEntityModel(ent, model);

    DispatchKeyValue(ent, "targetname", "portal_strike_portal");
    DispatchKeyValue(ent, "spawnflags", "8"); // Motion disabled

    char skinStr[4];
    IntToString(portalType, skinStr, sizeof(skinStr));
    DispatchKeyValue(ent, "skin", skinStr);

    TeleportEntity(ent, pos, ang, NULL_VECTOR);
    DispatchSpawn(ent);

    // 1. Attach Team-Colored Glowing Sprite rim around oval
    char colorStr[32];
    if (team == CS_TEAM_CT)
    {
        if (portalType == 0)
            strcopy(colorStr, sizeof(colorStr), "0 160 255");
        else
            strcopy(colorStr, sizeof(colorStr), "0 255 230");
    }
    else
    {
        if (portalType == 0)
            strcopy(colorStr, sizeof(colorStr), "255 120 0");
        else
            strcopy(colorStr, sizeof(colorStr), "255 210 0");
    }

    outGlow = CreateEntityByName("env_sprite");
    if (outGlow > 0 && IsValidEntity(outGlow))
    {
        DispatchKeyValue(outGlow, "model", SPRITE_PORTAL_GLOW);
        DispatchKeyValue(outGlow, "classname", "env_sprite");
        DispatchKeyValue(outGlow, "spawnflags", "1"); // Start on
        DispatchKeyValue(outGlow, "scale", "1.65");
        DispatchKeyValue(outGlow, "rendermode", "5"); // Additive
        DispatchKeyValue(outGlow, "rendercolor", colorStr);
        DispatchKeyValue(outGlow, "renderamt", "255");

        float spritePos[3];
        spritePos[0] = pos[0] + (hitNormal[0] * 1.5);
        spritePos[1] = pos[1] + (hitNormal[1] * 1.5);
        spritePos[2] = pos[2] + (hitNormal[2] * 1.5);

        TeleportEntity(outGlow, spritePos, ang, NULL_VECTOR);
        DispatchSpawn(outGlow);
    }

    // 2. Attach Dynamic Light to illuminate walls & floors in team color
    outLight = CreateEntityByName("light_dynamic");
    if (outLight > 0 && IsValidEntity(outLight))
    {
        DispatchKeyValue(outLight, "_light", colorStr);
        DispatchKeyValue(outLight, "brightness", "3");
        DispatchKeyValue(outLight, "distance", "160");
        DispatchKeyValue(outLight, "style", "0");

        TeleportEntity(outLight, pos, ang, NULL_VECTOR);
        DispatchSpawn(outLight);
        AcceptEntityInput(outLight, "TurnOn");
    }

    // 3. Attach Dynamic point_camera for Live See-Through Portal Projection
    outCamera = CreateEntityByName("point_camera");
    if (outCamera > 0 && IsValidEntity(outCamera))
    {
        char camName[32];
        Format(camName, sizeof(camName), "portal_cam_%d_%d", team, portalType);
        DispatchKeyValue(outCamera, "targetname", camName);
        DispatchKeyValue(outCamera, "FOV", "90");
        DispatchKeyValue(outCamera, "UseScreenAspectRatio", "1");
        DispatchKeyValue(outCamera, "spawnflags", "1");

        float camPos[3];
        camPos[0] = pos[0] + (hitNormal[0] * 8.0);
        camPos[1] = pos[1] + (hitNormal[1] * 8.0);
        camPos[2] = pos[2] + (hitNormal[2] * 8.0);

        TeleportEntity(outCamera, camPos, ang, NULL_VECTOR);
        DispatchSpawn(outCamera);
        ActivateEntity(outCamera);
        AcceptEntityInput(outCamera, "SetOn");
    }

    return ent;
}

void RemovePortalAtIndex(int index)
{
    if (index < 0 || index >= g_PortalCount)
    {
        return;
    }

    int ent = g_Portals[index].entity;
    int glow = g_Portals[index].glowEntity;
    int light = g_Portals[index].lightEntity;
    int cam = g_Portals[index].cameraEntity;

    if (ent > 0 && IsValidEntity(ent))
    {
        EmitSoundToAll(SOUND_PORTAL_CLOSE, ent, SNDCHAN_BODY, SNDLEVEL_NORMAL);
        AcceptEntityInput(ent, "Kill");
    }
    if (glow > 0 && IsValidEntity(glow))
    {
        AcceptEntityInput(glow, "Kill");
    }
    if (light > 0 && IsValidEntity(light))
    {
        AcceptEntityInput(light, "Kill");
    }
    if (cam > 0 && IsValidEntity(cam))
    {
        AcceptEntityInput(cam, "Kill");
    }

    for (int i = index; i < g_PortalCount - 1; i++)
    {
        g_Portals[i] = g_Portals[i + 1];
    }
    g_PortalCount--;
}

void ClearAllPortals()
{
    for (int i = 0; i < g_PortalCount; i++)
    {
        int ent = g_Portals[i].entity;
        int glow = g_Portals[i].glowEntity;
        int light = g_Portals[i].lightEntity;
        int cam = g_Portals[i].cameraEntity;

        if (ent > 0 && IsValidEntity(ent))
        {
            AcceptEntityInput(ent, "Kill");
        }
        if (glow > 0 && IsValidEntity(glow))
        {
            AcceptEntityInput(glow, "Kill");
        }
        if (light > 0 && IsValidEntity(light))
        {
            AcceptEntityInput(light, "Kill");
        }
        if (cam > 0 && IsValidEntity(cam))
        {
            AcceptEntityInput(cam, "Kill");
        }
    }
    g_PortalCount = 0;
}

int GetPartnerPortalIndex(int sourceIdx)
{
    int requiredPartnerType = (g_Portals[sourceIdx].portalType == 0) ? 1 : 0;
    int sourceTeam = g_Portals[sourceIdx].team;

    // 1. Direct Dual-Portal Link (Portal A <-> Portal B deployed by same team)
    for (int j = 0; j < g_PortalCount; j++)
    {
        if (j != sourceIdx && g_Portals[j].team == sourceTeam && g_Portals[j].portalType == requiredPartnerType)
        {
            return j;
        }
    }

    // 2. Universal Cross-Team Paired Link (Portal A <-> Portal B across opposing teams)
    for (int j = 0; j < g_PortalCount; j++)
    {
        if (j != sourceIdx && g_Portals[j].portalType == requiredPartnerType)
        {
            return j;
        }
    }

    return -1;
}

// ==============================================================
//  PHYSICS, TELEPORTATION & GRENADE/PROJECTILE TRAVERSAL ENGINE
// ==============================================================

public Action Timer_PortalPhysicsTick(Handle timer)
{
    if (g_PortalCount < 2)
    {
        return Plugin_Continue;
    }

    float now = GetGameTime();

    // 1. Player & Bot Seamless Teleportation
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
        {
            continue;
        }

        // Debounce recent teleportation (0.35s) to prevent oscillation
        if (now - g_LastTeleportTime[client] < 0.35)
        {
            continue;
        }

        // Universal cross-team centroid & bounds calculation
        float playerPos[3], playerEye[3];
        GetClientAbsOrigin(client, playerPos);
        GetClientEyePosition(client, playerEye);
        float midPos[3];
        midPos[0] = playerPos[0];
        midPos[1] = playerPos[1];
        midPos[2] = (playerPos[2] + playerEye[2]) * 0.5;

        for (int i = 0; i < g_PortalCount; i++)
        {
            float distMid = GetVectorDistance(midPos, g_Portals[i].pos);
            float distFeet = GetVectorDistance(playerPos, g_Portals[i].pos);
            float distEye = GetVectorDistance(playerEye, g_Portals[i].pos);

            // Universal traversal trigger: CT and T can freely use any active portal
            if (distMid <= 58.0 || distFeet <= 54.0 || distEye <= 54.0)
            {
                int targetIdx = GetPartnerPortalIndex(i);
                if (targetIdx != -1)
                {
                    TeleportPlayerThroughPortal(client, i, targetIdx);
                    g_LastTeleportTime[client] = now;
                    break;
                }
            }
        }
    }

    // 2. Projectile Traversal (HE Grenades, Flashbangs, Smoke Grenades)
    ProcessGrenadeTraversal();

    return Plugin_Continue;
}

void TeleportPlayerThroughPortal(int client, int sourceIdx, int destIdx)
{
    if (sourceIdx < 0 || destIdx < 0) return;
    float destPos[3], exitVelocity[3], destAng[3];
    destPos = g_Portals[destIdx].pos;

    // Push player cleanly outward along the destination portal's forward vector
    destPos[0] += g_Portals[destIdx].forwardVec[0] * 56.0;
    destPos[1] += g_Portals[destIdx].forwardVec[1] * 56.0;

    // Viewing angle and position adjustment based on surface orientation
    float playerEyeAng[3];
    GetClientEyeAngles(client, playerEyeAng);

    if (FloatAbs(g_Portals[destIdx].forwardVec[2]) < 0.7)
    {
        // Wall portal: standard player height offset so feet don't clip into floor
        destPos[2] += (g_Portals[destIdx].forwardVec[2] * 56.0) - 24.0;
        destAng[0] = playerEyeAng[0]; // preserve pitch (view elevation)
        destAng[1] = g_Portals[destIdx].angles[1]; // reorient yaw outward from exit portal
        destAng[2] = 0.0;
    }
    else if (g_Portals[destIdx].forwardVec[2] > 0.7)
    {
        // Floor portal: launch upward cleanly
        destPos[2] += 48.0;
        destAng[0] = 0.0;
        destAng[1] = playerEyeAng[1];
        destAng[2] = 0.0;
    }
    else
    {
        // Ceiling portal: drop downward cleanly
        destPos[2] -= 72.0;
        destAng[0] = 0.0;
        destAng[1] = playerEyeAng[1];
        destAng[2] = 0.0;
    }

    // Preserve player velocity & momentum magnitude, reoriented along exit normal
    float curVel[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", curVel);
    float speed = GetVectorLength(curVel);
    if (speed < 260.0) speed = 260.0; // Maintain tactical entry momentum

    exitVelocity[0] = g_Portals[destIdx].forwardVec[0] * speed;
    exitVelocity[1] = g_Portals[destIdx].forwardVec[1] * speed;
    exitVelocity[2] = g_Portals[destIdx].forwardVec[2] * speed;

    TeleportEntity(client, destPos, destAng, exitVelocity);
    EmitSoundToAll(SOUND_PORTAL_OPEN, client, SNDCHAN_BODY, SNDLEVEL_NORMAL);

    // Fall Damage Enforcement:
    // If exit velocity has high downward momentum, set m_flFallVelocity so native CS:S
    // engine correctly calculates and inflicts standard fall damage upon landing on ground
    if (exitVelocity[2] < -350.0)
    {
        SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", FloatAbs(exitVelocity[2]));
    }
}

void ProcessGrenadeTraversal()
{
    // Scan all active grenade entities in the world
    static const char grenadeClasses[][] = {
        "hegrenade_projectile",
        "flashbang_projectile",
        "smokegrenade_projectile"
    };

    for (int c = 0; c < sizeof(grenadeClasses); c++)
    {
        int ent = -1;
        while ((ent = FindEntityByClassname(ent, grenadeClasses[c])) != -1)
        {
            if (!IsValidEntity(ent)) continue;

            float grenPos[3];
            GetEntPropVector(ent, Prop_Data, "m_vecOrigin", grenPos);

            for (int i = 0; i < g_PortalCount; i++)
            {
                if (GetVectorDistance(grenPos, g_Portals[i].pos) <= 50.0)
                {
                    int destIdx = GetPartnerPortalIndex(i);
                    if (destIdx != -1)
                    {
                        TeleportProjectileThroughPortal(ent, i, destIdx);
                        break;
                    }
                }
            }
        }
    }
}

void TeleportProjectileThroughPortal(int entity, int sourceIdx, int destIdx)
{
    if (sourceIdx < 0 || destIdx < 0) return;
    float destPos[3], curVel[3], exitVelocity[3], destAng[3];
    destPos = g_Portals[destIdx].pos;
    destAng = g_Portals[destIdx].angles;

    GetEntPropVector(entity, Prop_Data, "m_vecVelocity", curVel);
    float speed = GetVectorLength(curVel);
    if (speed < 300.0) speed = 300.0; // Maintain high grenade ejection speed

    // Offset grenade position outside exit portal plane
    destPos[0] += g_Portals[destIdx].forwardVec[0] * 48.0;
    destPos[1] += g_Portals[destIdx].forwardVec[1] * 48.0;
    destPos[2] += g_Portals[destIdx].forwardVec[2] * 48.0;

    exitVelocity[0] = g_Portals[destIdx].forwardVec[0] * speed;
    exitVelocity[1] = g_Portals[destIdx].forwardVec[1] * speed;
    exitVelocity[2] = g_Portals[destIdx].forwardVec[2] * speed;

    TeleportEntity(entity, destPos, destAng, exitVelocity);
    EmitSoundToAll(SOUND_PORTAL_OPEN, entity, SNDCHAN_BODY, SNDLEVEL_NORMAL);
}

// ==============================================================
//  BULLET & LINE-OF-SIGHT HIT REGISTRATION ACROSS PORTALS
// ==============================================================

public Action Hook_PlayerTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    // If victim was hit through normal line of sight, allow normal processing
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && g_PortalCount >= 2)
    {
        // Check if attacker aimed near an active portal
        float eyePos[3], eyeAng[3];
        GetClientEyePosition(attacker, eyePos);
        GetClientEyeAngles(attacker, eyeAng);

        Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SHOT, RayType_Infinite, Filter_WorldOnly);
        if (TR_DidHit(trace))
        {
            float hitPos[3];
            TR_GetEndPosition(hitPos, trace);

            for (int i = 0; i < g_PortalCount; i++)
            {
                if (GetVectorDistance(hitPos, g_Portals[i].pos) <= 48.0)
                {
                    int destIdx = GetPartnerPortalIndex(i);
                    if (destIdx != -1)
                    {
                        // Bullet crossed into entry portal: perform secondary raycast from exit portal
                        TraceBulletsThroughExitPortal(attacker, destIdx, damage, damagetype);
                    }
                    break;
                }
            }
        }
        delete trace;
    }

    return Plugin_Continue;
}

void TraceBulletsThroughExitPortal(int attacker, int destIdx, float damage, int damagetype)
{
    float exitStart[3], exitDir[3], exitAngles[3];
    exitStart = g_Portals[destIdx].pos;
    exitAngles = g_Portals[destIdx].angles;
    exitDir = g_Portals[destIdx].forwardVec;

    exitStart[0] += exitDir[0] * 32.0;
    exitStart[1] += exitDir[1] * 32.0;
    exitStart[2] += exitDir[2] * 32.0;

    // Trace outward from exit portal
    Handle trace = TR_TraceRayFilterEx(exitStart, exitAngles, MASK_SHOT, RayType_Infinite, Filter_WorldOnly);
    if (TR_DidHit(trace))
    {
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);

        // Visual tracer line exiting the portal
        if (g_GlowSpriteIndex > 0)
        {
            int color[4] = { 255, 200, 50, 220 };
            TE_SetupBeamPoints(exitStart, hitPos, g_GlowSpriteIndex, g_HaloSpriteIndex, 0, 30, 0.25, 2.0, 2.0, 0, 0.0, color, 0);
            TE_SendToAll();
        }

        // Hit registration on enemies in exit trajectory
        for (int victim = 1; victim <= MaxClients; victim++)
        {
            if (IsClientInGame(victim) && IsPlayerAlive(victim) && victim != attacker)
            {
                float vicPos[3];
                GetClientAbsOrigin(victim, vicPos);
                vicPos[2] += 36.0;

                // Point-to-line segment distance calculation
                float d = GetDistanceToLine(vicPos, exitStart, hitPos);
                if (d <= 32.0)
                {
                    SDKHooks_TakeDamage(victim, attacker, attacker, damage, damagetype);
                    break;
                }
            }
        }
    }
    delete trace;
}

float GetDistanceToLine(const float point[3], const float lineStart[3], const float lineEnd[3])
{
    float lineVec[3], pointVec[3];
    SubtractVectors(lineEnd, lineStart, lineVec);
    SubtractVectors(point, lineStart, pointVec);

    float lineLen = GetVectorLength(lineVec);
    if (lineLen < 0.001) return GetVectorDistance(point, lineStart);

    NormalizeVector(lineVec, lineVec);
    float dot = GetVectorDotProduct(pointVec, lineVec);
    if (dot < 0.0) return GetVectorDistance(point, lineStart);
    if (dot > lineLen) return GetVectorDistance(point, lineEnd);

    float projPoint[3];
    projPoint[0] = lineStart[0] + (lineVec[0] * dot);
    projPoint[1] = lineStart[1] + (lineVec[1] * dot);
    projPoint[2] = lineStart[2] + (lineVec[2] * dot);

    return GetVectorDistance(point, projPoint);
}

// ==============================================================
//  UNIVERSAL END-OF-ROUND FINAL KILLCAM (CALL OF DUTY STYLE)
// ==============================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    bool headshot = event.GetBool("headshot");

    if (victim > 0 && IsClientInGame(victim))
    {
        int victimTeam = GetClientTeam(victim);

        // Exclusive Single-Bearer Dynamic Death Reallocation:
        if ((victimTeam == CS_TEAM_T || victimTeam == CS_TEAM_CT) && g_TeamPortalBearer[victimTeam] == victim)
        {
            g_PortalModeActive[victim] = false;
            RestoreOriginalViewmodel(victim);

            // Find surviving teammates to reallocate the portal gun
            int survivors[MAXPLAYERS + 1];
            int survCount = 0;
            int humanSurvivor = -1;

            for (int i = 1; i <= MaxClients; i++)
            {
                if (i != victim && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == victimTeam)
                {
                    survivors[survCount++] = i;
                    if (!IsFakeClient(i))
                    {
                        humanSurvivor = i;
                    }
                }
            }

            if (survCount > 0)
            {
                int newBearer = (humanSurvivor != -1) ? humanSurvivor : survivors[GetRandomInt(0, survCount - 1)];
                g_TeamPortalBearer[victimTeam] = newBearer;

                char oldName[MAX_NAME_LENGTH], newName[MAX_NAME_LENGTH];
                GetClientName(victim, oldName, sizeof(oldName));
                GetClientName(newBearer, newName, sizeof(newName));

                PrintToChatAll("[Portal Strike] Portal Bearer %s eliminated! Portal Gun reallocated to %s.", oldName, newName);

                if (!IsFakeClient(newBearer))
                {
                    PrintCenterText(newBearer, "[PORTAL GUN REALLOCATED TO YOU]\nYou are now the designated Portal Bearer!");
                    PrintToChat(newBearer, "[Portal Strike] Portal Gun acquired! Press [F] or [T] to deploy portals.");
                    EmitSoundToClient(newBearer, SOUND_PORTAL_ARM, SOUND_FROM_PLAYER, SNDCHAN_ITEM, SNDLEVEL_NORMAL);
                }
            }
            else
            {
                g_TeamPortalBearer[victimTeam] = -1;
            }
        }
    }

    if (victim > 0 && attacker > 0 && attacker != victim && IsClientInGame(attacker))
    {
        g_LastKill.killer = attacker;
        g_LastKill.victim = victim;
        GetClientName(attacker, g_LastKill.killerName, sizeof(g_LastKill.killerName));

        if (IsClientInGame(victim))
        {
            GetClientName(victim, g_LastKill.victimName, sizeof(g_LastKill.victimName));
            GetClientAbsOrigin(victim, g_LastKill.victimPos);
        }
        else
        {
            Format(g_LastKill.victimName, sizeof(g_LastKill.victimName), "Target");
        }

        GetClientAbsOrigin(attacker, g_LastKill.killerPos);
        GetClientEyeAngles(attacker, g_LastKill.killerAng);
        strcopy(g_LastKill.weapon, sizeof(g_LastKill.weapon), weapon);
        g_LastKill.headshot = headshot;
        g_LastKill.timestamp = GetGameTime();
        g_LastKill.valid = true;
    }
}

void StartKillcam()
{
    if (!g_CvarKillcam.BoolValue)
    {
        return;
    }

    if (!g_LastKill.valid)
    {
        return;
    }

    // Kill must have occurred recently (within current round end window)
    if (GetGameTime() - g_LastKill.timestamp > 15.0)
    {
        return;
    }

    EndKillcam(); // Clean up any active camera

    // Calculate reverse-time trajectory (victim -> killer)
    float dir[3], fwdVec[3], rightVec[3], shotAng[3];
    SubtractVectors(g_LastKill.victimPos, g_LastKill.killerPos, dir);
    float dist = GetVectorLength(dir);
    if (dist < 80.0) dist = 80.0;

    GetVectorAngles(dir, shotAng);
    GetAngleVectors(shotAng, fwdVec, rightVec, NULL_VECTOR);

    // Camera Start: Positioned in front of victim's death position looking at the fatal impact
    g_KillcamStartPos[0] = g_LastKill.victimPos[0] - (fwdVec[0] * 50.0);
    g_KillcamStartPos[1] = g_LastKill.victimPos[1] - (fwdVec[1] * 50.0);
    g_KillcamStartPos[2] = g_LastKill.victimPos[2] + 42.0;

    // Camera End: Positioned behind killer's shoulder looking along the line of fire
    g_KillcamEndPos[0] = g_LastKill.killerPos[0] - (fwdVec[0] * 75.0) + (rightVec[0] * 22.0);
    g_KillcamEndPos[1] = g_LastKill.killerPos[1] - (fwdVec[1] * 75.0) + (rightVec[1] * 22.0);
    g_KillcamEndPos[2] = g_LastKill.killerPos[2] + 46.0;

    g_KillcamTargetPos = g_LastKill.victimPos;
    g_KillcamTargetPos[2] += 32.0; // Aim at chest / head of victim

    // Spawn point_viewcontrol camera
    int cam = CreateEntityByName("point_viewcontrol");
    if (cam > 0 && IsValidEntity(cam))
    {
        DispatchKeyValue(cam, "targetname", "portal_killcam_cam");
        DispatchKeyValue(cam, "spawnflags", "12"); // Freeze Player (8) + Infinite Hold (4)

        float initialAng[3], lookDir[3];
        SubtractVectors(g_KillcamTargetPos, g_KillcamStartPos, lookDir);
        GetVectorAngles(lookDir, initialAng);

        TeleportEntity(cam, g_KillcamStartPos, initialAng, NULL_VECTOR);
        DispatchSpawn(cam);
        ActivateEntity(cam);

        g_KillcamEntity = cam;
        g_KillcamActive = true;
        g_KillcamTicks = 0;

        // Switch all connected players (alive, dead, spectating) to cinematic killcam
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                AcceptEntityInput(cam, "Enable", i);
                SetClientViewEntity(i, cam);
            }
        }

        CreateTimer(0.05, Timer_KillcamTick, _, TIMER_REPEAT);
    }
}

public Action Timer_KillcamTick(Handle timer)
{
    if (!g_KillcamActive || g_KillcamEntity <= 0 || !IsValidEntity(g_KillcamEntity))
    {
        EndKillcam();
        return Plugin_Stop;
    }

    g_KillcamTicks++;

    float duration = g_CvarKillcamDuration.FloatValue;
    int maxTicks = RoundToFloor(duration / 0.05);
    if (maxTicks < 20) maxTicks = 20;

    if (g_KillcamTicks > maxTicks)
    {
        EndKillcam();
        return Plugin_Stop;
    }

    float totalFrac = float(g_KillcamTicks) / float(maxTicks);

    float currentPos[3], currentAng[3], lookDir[3];

    // Reverse-Time Interpolation:
    // 0.00 - 0.20: Focus on victim elimination impact
    // 0.20 - 0.85: Smooth cinematic rewind pan from victim backward to killer
    // 0.85 - 1.00: Lock onto killer taking the shot
    if (totalFrac < 0.20)
    {
        currentPos = g_KillcamStartPos;
        SubtractVectors(g_KillcamTargetPos, currentPos, lookDir);
        GetVectorAngles(lookDir, currentAng);
    }
    else if (totalFrac < 0.85)
    {
        float rewindFrac = (totalFrac - 0.20) / 0.65;
        float smoothFrac = rewindFrac * (2.0 - rewindFrac); // Smooth quadratic ease-out
        currentPos[0] = g_KillcamStartPos[0] + (g_KillcamEndPos[0] - g_KillcamStartPos[0]) * smoothFrac;
        currentPos[1] = g_KillcamStartPos[1] + (g_KillcamEndPos[1] - g_KillcamStartPos[1]) * smoothFrac;
        currentPos[2] = g_KillcamStartPos[2] + (g_KillcamEndPos[2] - g_KillcamStartPos[2]) * smoothFrac;

        SubtractVectors(g_KillcamTargetPos, currentPos, lookDir);
        GetVectorAngles(lookDir, currentAng);
    }
    else
    {
        currentPos = g_KillcamEndPos;
        SubtractVectors(g_KillcamTargetPos, currentPos, lookDir);
        GetVectorAngles(lookDir, currentAng);
    }

    TeleportEntity(g_KillcamEntity, currentPos, currentAng, NULL_VECTOR);

    // Call of Duty-style Reverse-Time HUD banner broadcast to all players
    char hsText[24];
    Format(hsText, sizeof(hsText), g_LastKill.headshot ? " [HEADSHOT]" : "");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SetHudTextParams(-1.0, 0.12, 0.1, 255, 60, 60, 240, 0, 0.0, 0.0, 0.0);
            ShowHudText(i, 1, "★ REVERSE-TIME KILLCAM ★\n<< REWIND PLAYBACK <<\n%s  [%s]  %s%s", 
                g_LastKill.killerName, g_LastKill.weapon, g_LastKill.victimName, hsText);
        }
    }

    return Plugin_Continue;
}

void EndKillcam()
{
    if (g_KillcamActive)
    {
        g_KillcamActive = false;

        if (g_KillcamEntity > 0 && IsValidEntity(g_KillcamEntity))
        {
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i))
                {
                    AcceptEntityInput(g_KillcamEntity, "Disable", i);
                    SetClientViewEntity(i, i);
                }
            }
            AcceptEntityInput(g_KillcamEntity, "Kill");
            g_KillcamEntity = -1;
        }
    }
}

void AssignInitialPortalBearers()
{
    g_TeamPortalBearer[CS_TEAM_T] = -1;
    g_TeamPortalBearer[CS_TEAM_CT] = -1;

    // Step 1: For any team containing a human player, human player is ALWAYS the designated portal bearer!
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            int t = GetClientTeam(i);
            if (t == CS_TEAM_T || t == CS_TEAM_CT)
            {
                g_TeamPortalBearer[t] = i;
            }
        }
    }

    // Step 2: For any team without an assigned bearer (e.g. opposing bot team), pick a random alive bot
    for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
    {
        if (g_TeamPortalBearer[team] <= 0 || !IsClientInGame(g_TeamPortalBearer[team]))
        {
            int bots[MAXPLAYERS + 1];
            int count = 0;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && GetClientTeam(i) == team)
                {
                    bots[count++] = i;
                }
            }
            if (count > 0)
            {
                g_TeamPortalBearer[team] = bots[GetRandomInt(0, count - 1)];
            }
        }
    }

    // Announce designated bearers to human players
    for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
    {
        int bearer = g_TeamPortalBearer[team];
        if (bearer > 0 && IsClientInGame(bearer) && !IsFakeClient(bearer))
        {
            PrintCenterText(bearer, "[DESIGNATED PORTAL BEARER]\nYou possess the Portal Gun for your team!");
            PrintToChat(bearer, "[Portal Strike] You are your team's designated Portal Bearer. Press [F] or [T] to deploy portals.");
        }
    }
}
