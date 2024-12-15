#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>


public Plugin myinfo = {
    name        = "WitchAnnounce",
    author      = "CanadaRox, TouchMe",
    description = "Prints damage done to witches",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_witch_announce"
};


#define ENTITY_NAME_LENGTH 64
#define DMG_BURN (1 << 3) /**< heat burned */

/*
 *
 */
#define WORLD_INDEX            0

/*
 * Infected Class.
 */
#define SI_CLASS_TANK           8

/*
 * Team.
 */
#define TEAM_NONE               0
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define TRANSLATIONS            "witch_announce.phrases"

/**
 * Entity-Relationship: UserVector(Userid, ...)
 */
methodmap UserVector < ArrayList {
    public UserVector(int iBlockSize = 1) {
        return view_as<UserVector>(new ArrayList(iBlockSize + 1, 0)); // extended by 1 cell for userid field
    }

    public any Get(int iIdx, int iType) {
        return GetArrayCell(this, iIdx, iType + 1);
    }

    public void Set(int iIdx, any val, int iType) {
        SetArrayCell(this, iIdx, val, iType + 1);
    }

    public int Ent(int iIdx) {
        return GetArrayCell(this, iIdx, 0);
    }

    public int Push(any val) {
        int iBlockSize = this.BlockSize;

        any[] array = new any[iBlockSize];
        array[0] = val;
        for (int i = 1; i < iBlockSize; i++) {
            array[i] = 0;
        }

        return this.PushArray(array);
    }

    public bool EntIndex(int iEnt, int &iIdx, bool bCreate = false) {
        if (this == null)
            return false;

        iIdx = this.FindValue(iEnt, 0);
        if (iIdx == -1) {
            if (!bCreate)
                return false;

            iIdx = this.Push(iEnt);
        }

        return true;
    }

    public bool EntGet(int iEnt, int iType, any &val) {
        int iIdx;
        if (!this.EntIndex(iEnt, iIdx, false))
            return false;

        val = this.Get(iIdx, iType);
        return true;
    }

    public bool EntSet(int iEnt, int iType, any val, bool bCreate = false) {
        int iIdx;
        if (!this.EntIndex(iEnt, iIdx, bCreate))
            return false;

        this.Set(iIdx, val, iType);
        return true;
    }

    public bool EntAdd(int iUserId, int iType, any amount, bool bCreate = false) {
        int iIdx;
        if (!this.EntIndex(iUserId, iIdx, bCreate))
            return false;

        int val = this.Get(iIdx, iType);
        this.Set(iIdx, val + amount, iType);
        return true;
    }
}

enum {
    eDmgDone,        // Damage to Witch
    eTeamIdx,        // Team color
    eHarrasser,      // Is harrasser
    eArsonist,       // Is arsonist
    eDamagerInfoSize // Size
};

enum {
    eWitchIndex,         // Serial number of Witch spawned on this map
    eWitchLastHealth,    // Last HP after hit
    eWitchMaxHealth,     // Max HP
    eWitchHarrasser,     // Witch Harrasser
    eWitchArsonist,      // Witch Arsonist
    eDamagerInfoVector,  // UserVector storing info described above
    eWitchInfoSize       // Size
};

UserVector g_aWitchInfo = null;     // Every Witch has a slot here along with relationships.
StringMap  g_smUserNames = null;    // Simple map from userid to player names.

ConVar g_cvWitchHealth = null;
int    g_iWitchIdx     = 0; 
int    g_iWitchHealth  = 0;


public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    HookEvent("round_start",                Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end",                  Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("witch_spawn",                Event_WitchSpawn);
    HookEvent("witch_harasser_set",         Event_WitchHarasserSet);
    HookEvent("infected_hurt",              Event_InfectedHurt);
    HookEvent("witch_killed",               Event_WitchKilled);
    HookEvent("player_hurt",                Event_PlayerHurt);
    HookEvent("player_incapacitated_start", Event_PlayerIncap);

    g_cvWitchHealth = FindConVar("z_witch_health");
    g_iWitchHealth = g_cvWitchHealth.IntValue;
    g_cvWitchHealth.AddChangeHook(ConVarChanged);

    g_aWitchInfo  = new UserVector(eWitchInfoSize);
    g_smUserNames = new StringMap();

    int iEntityMaxCount = GetEntityCount();
    for (int iEnt = MaxClients + 1; iEnt <= iEntityMaxCount; iEnt++)
    {
        if (!IsEntityWitch(iEnt)) {
            continue;
        }

        g_aWitchInfo.EntSet(iEnt, eWitchIndex, ++g_iWitchIdx);
        g_aWitchInfo.EntSet(iEnt, eDamagerInfoVector, new UserVector(eDamagerInfoSize), true);
        g_aWitchInfo.EntSet(iEnt, eWitchLastHealth, g_iWitchHealth);
        g_aWitchInfo.EntSet(iEnt, eWitchMaxHealth, g_iWitchHealth);
        g_aWitchInfo.EntSet(iEnt, eWitchHarrasser, -1);
        g_aWitchInfo.EntSet(iEnt, eWitchArsonist, -1);
    }
}

public void OnClientDisconnect(int iClient)
{
    int iUserId = GetClientUserId(iClient);

    char szKey[16];
    IntToString(iUserId, szKey, sizeof(szKey));

    char szClientName[MAX_NAME_LENGTH];
    GetClientNameFixed(iClient, szClientName, sizeof(szClientName), 18);
    g_smUserNames.SetString(szKey, szClientName);
}

void ConVarChanged(ConVar cv, const char[] szOldValie, const char[] szNewValue) {
    g_iWitchHealth = g_cvWitchHealth.IntValue;
}

void Event_RoundStart(Event event, const char[] szEventName, bool bDontBroadcast)
{
    g_iWitchIdx = 0;
    SetupWitchInfo();
    g_smUserNames.Clear();
}

void Event_RoundEnd(Event event, const char[] szEventName, bool bDontBroadcast)
{
    g_iWitchIdx = 0;
    SetupWitchInfo();
    g_smUserNames.Clear();
}

void Event_WitchSpawn(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iWitch = GetEventInt(event, "witchid");
    g_aWitchInfo.EntSet(iWitch, eWitchIndex, ++g_iWitchIdx);
    g_aWitchInfo.EntSet(iWitch, eDamagerInfoVector, new UserVector(eDamagerInfoSize), true);
    g_aWitchInfo.EntSet(iWitch, eWitchLastHealth, g_iWitchHealth);
    g_aWitchInfo.EntSet(iWitch, eWitchMaxHealth, g_iWitchHealth);
    g_aWitchInfo.EntSet(iWitch, eWitchHarrasser, -1);
    g_aWitchInfo.EntSet(iWitch, eWitchArsonist, -1);
}

void Event_WitchHarasserSet(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iWitch = GetEventInt(event, "witchid");
    int iAttackerId = GetEventInt(event, "userid");
    int iAttacker = GetClientOfUserId(iAttackerId);

    if (!IsValidClient(iAttacker) || !IsClientSurvivor(iAttacker)) {
        return;
    }

    g_aWitchInfo.EntSet(iWitch, eWitchHarrasser, iAttackerId);

    UserVector uDamagerVector;
    g_aWitchInfo.EntGet(iWitch, eDamagerInfoVector, uDamagerVector);
    uDamagerVector.EntSet(iAttackerId, eHarrasser, true, true);
    uDamagerVector.EntSet(iAttackerId, eTeamIdx, TEAM_SURVIVOR, true);
}

void Event_InfectedHurt(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iWitch = GetEventInt(event, "entityid");
    if (!IsEntityWitch(iWitch)) {
        return;
    }

    int iAttackerId = GetEventInt(event, "attacker");
    int iAttacker   = GetClientOfUserId(iAttackerId);

    if (iAttacker == WORLD_INDEX) {
        iAttackerId = 0;
        iAttacker   = 0;
    }

    int iWitchArsonistId;
    g_aWitchInfo.EntGet(iWitch, eWitchArsonist, iWitchArsonistId);

    int iWitchHarrasserId;
    g_aWitchInfo.EntGet(iWitch, eWitchHarrasser, iWitchHarrasserId);

    int iType = GetEventInt(event, "type");
    if (iType == DMG_BURN && iWitchArsonistId == -1)
    {
        g_aWitchInfo.EntSet(iWitch, eWitchArsonist, iAttackerId);

        UserVector uDamagerVector;
        g_aWitchInfo.EntGet(iWitch, eDamagerInfoVector, uDamagerVector);
        uDamagerVector.EntSet(iAttackerId, eArsonist, true, true);

        iWitchArsonistId = iAttackerId;
    }

    if (iAttacker == WORLD_INDEX)
    {
        int iWitchArsonist  = GetClientOfUserId(iWitchArsonistId);
        int iWitchHarrasser = GetClientOfUserId(iWitchHarrasserId);

        if (IsValidClient(iWitchArsonist) && IsClientSurvivor(iWitchArsonist))
        {
            iAttackerId = iWitchArsonistId;
            iAttacker   = iWitchArsonist;
        }
        else if (IsValidClient(iWitchHarrasser) && IsClientSurvivor(iWitchHarrasser))
        {
            iAttackerId = iWitchHarrasserId;
            iAttacker   = iWitchHarrasser;
        }
    }

    int iTeam = TEAM_NONE;
    if (iAttacker > 0 && IsClientInGame(iAttacker)) {
        iTeam = GetClientTeam(iAttacker);
    }

    int iLastHealth;
    g_aWitchInfo.EntGet(iWitch, eWitchLastHealth, iLastHealth);

    int iDmg = GetEventInt(event, "amount");
    if (iDmg >= iLastHealth) {
        iDmg = iLastHealth;
    }

    g_aWitchInfo.EntSet(iWitch, eWitchLastHealth, iLastHealth - iDmg);

    UserVector uDamagerVector;
    g_aWitchInfo.EntGet(iWitch, eDamagerInfoVector, uDamagerVector);
    uDamagerVector.EntAdd(iAttackerId, eDmgDone, iDmg, true);
    uDamagerVector.EntSet(iAttackerId, eTeamIdx, iTeam, true);
}

void Event_WitchKilled(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iWitch = GetEventInt(event, "witchid");
    int iAttackerId = GetEventInt(event, "userid");

    int iAttacker = GetClientOfUserId(iAttackerId);
    if (iAttacker == WORLD_INDEX)
    {
        int iWitchArsonistId;
        g_aWitchInfo.EntGet(iWitch, eWitchArsonist, iWitchArsonistId);

        int iWitchHarrasserId;
        g_aWitchInfo.EntGet(iWitch, eWitchHarrasser, iWitchHarrasserId);

        int iWitchArsonist  = GetClientOfUserId(iWitchArsonistId);
        int iWitchHarrasser = GetClientOfUserId(iWitchHarrasserId);

        if (IsValidClient(iWitchArsonist) && IsClientSurvivor(iWitchArsonist))
        {
            iAttackerId = iWitchArsonistId;
            iAttacker   = iWitchArsonist;
        }
        else if (IsValidClient(iWitchHarrasser) && IsClientSurvivor(iWitchHarrasser))
        {
            iAttackerId = iWitchHarrasserId;
            iAttacker   = iWitchHarrasser;
        }
        else
        {
            iAttackerId = 0;
            iAttacker   = 0;
        }
    }

    int iIdx = 0;
    bool bOneShot = GetEventBool(event, "oneshot");

    if (bOneShot == false)
    {
        int iLastHealth;
        g_aWitchInfo.EntGet(iWitch, eWitchLastHealth, iLastHealth);
        g_aWitchInfo.EntSet(iWitch, eWitchLastHealth, 0);

        UserVector uDamagerVector;
        g_aWitchInfo.EntGet(iWitch, eDamagerInfoVector, uDamagerVector);
        uDamagerVector.EntAdd(iAttackerId, eDmgDone, iLastHealth, true);

        PrintWitchInfo(iWitch);
    }

    else if (g_aWitchInfo.EntIndex(iWitch, iIdx, false))
    {
        char szClientName[MAX_NAME_LENGTH];

        GetClientNameFromUserId(iAttackerId, szClientName, sizeof(szClientName));

        if (IsClientSurvivor(iAttacker)) {
            CPrintToChatAll("%t%t", "TAG", "ONESHOT", szClientName);
        } else if (IsClientInfected(iAttacker) && IsClientTank(iAttacker)) {
            CPrintToChatAll("%t%t", "TAG", "ONEPUNCH", szClientName);
        }
    }

    ClearWitchInfo(iWitch);
}

void Event_PlayerHurt(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (iVictim <= 0 || !IsClientSurvivor(iVictim)) {
        return;
    }

    int iWitch = GetEventInt(event, "attackerentid");
    if (!IsEntityWitch(iWitch)) {
        return;
    }

    int iDmg = GetEventInt(event, "dmg_health");
    if (iDmg == 0) {
        return;
    }

    PrintWitchInfo(iWitch);
    ClearWitchInfo(iWitch);
}

void Event_PlayerIncap(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (iVictim <= 0 || !IsClientSurvivor(iVictim)) {
        return;
    }

    int iWitch = GetEventInt(event, "attackerentid");
    if (!IsEntityWitch(iWitch)) {
        return;
    }

    PrintWitchInfo(iWitch);
    ClearWitchInfo(iWitch);
}

public void OnEntityDestroyed(int iEnt)
{
    if (!IsEntityWitch(iEnt)) {
        return;
    }

    ClearWitchInfo(iEnt);
}

void PrintWitchInfo(int iWitchEnt)
{
    static const char szTeamColor[][] = {
        "{olive}",
        "{olive}",
        "{blue}",
        "{red}"
    };

    int iLength = g_aWitchInfo.Length;
    if (!iLength) {
        return;
    }

    int iIdx = 0;
    if (!g_aWitchInfo.EntIndex(iWitchEnt, iIdx, false)) {
        return;
    }

    int iLastHealth = g_aWitchInfo.Get(iIdx, eWitchLastHealth);
    int iMaxHealth  = g_aWitchInfo.Get(iIdx, eWitchMaxHealth);

    UserVector uDamagerVector = g_aWitchInfo.Get(iIdx, eDamagerInfoVector);
    uDamagerVector.SortCustom(SortAdtDamageDesc);

    int iDmgTtl = 0, iPctTtl = 0, iSize = uDamagerVector.Length;
    for (int i = 0; i < iSize; i++)
    {
        iDmgTtl += uDamagerVector.Get(i, eDmgDone);
        iPctTtl += GetDamageAsPercent(uDamagerVector.Get(i, eDmgDone), iMaxHealth);
    }

    if (iLastHealth == 0) {
        CPrintToChatAll("%t%t%t", "BRACKET_START", "TAG", "DEAD");
    } else {
        CPrintToChatAll("%t%t%t", "BRACKET_START", "TAG", "INCAP", iLastHealth);
    }

    char szClientName[MAX_NAME_LENGTH];
    int  iDmg, iPct, iTeamIdx;

    int iPctAdjustment;
    if (iPctTtl < 100 && float(iDmgTtl) > (iMaxHealth - (iMaxHealth / 200))) {
        iPctAdjustment = 100 - iPctTtl;
    }

    int iLastPct = 100;
    int iAdjustedPctDmg;
    for (int iAttacker = 0; iAttacker < iSize; iAttacker++)
    {
        // generally needed
        GetClientNameFromUserId(uDamagerVector.Ent(iAttacker), szClientName, sizeof(szClientName));

        // basic witch damage announce
        iTeamIdx = uDamagerVector.Get(iAttacker, eTeamIdx);

        iDmg = uDamagerVector.Get(iAttacker, eDmgDone);

        iPct = GetDamageAsPercent(iDmg, iMaxHealth);
        if (iPctAdjustment != 0 && iDmg > 0 && !IsExactPercent(iDmg, iMaxHealth))
        {
            iAdjustedPctDmg = iPct + iPctAdjustment;

            if (iAdjustedPctDmg <= iLastPct)
            {
                iPct = iAdjustedPctDmg;
                iPctAdjustment = 0;
            }
        }

        // ignore cases printing zeros only except harrasser and arsonist
        bool bArsonist  = uDamagerVector.Get(iAttacker, eArsonist);
        bool bHarrasser = uDamagerVector.Get(iAttacker, eHarrasser);
        if (iDmg > 0 || bHarrasser || bArsonist)
        {
            char szDmgSpace[16];
            FormatEx(szDmgSpace, sizeof(szDmgSpace), "%s",
            iDmg < 10 ? "      " : iDmg < 100 ? "    " : iDmg < 1000 ? "  " : "");

            char szPrcntSpace[16];
            FormatEx(szPrcntSpace, sizeof(szPrcntSpace), "%s",
            iPct < 10 ? "  " : iPct < 100 ? " " : "");

            CPrintToChatAll("%t%t", (iAttacker + 1) == iSize ? "BRACKET_END" : "BRACKET_MIDDLE", "DAMAGE", szDmgSpace, iDmg, szPrcntSpace, iPct, szPrcntSpace, bHarrasser ? "»" : "", szTeamColor[iTeamIdx], szClientName, bHarrasser ? "«" : "");
        }
    }
}

void ClearWitchInfo(int iWitchEnt)
{
    int iIdx = 0;
    if (!g_aWitchInfo.EntIndex(iWitchEnt, iIdx, false)) {
        return;
    }

    UserVector uDamagerVector = g_aWitchInfo.Get(iIdx, eDamagerInfoVector);
    delete uDamagerVector;

    g_aWitchInfo.Erase(iIdx);
}

void SetupWitchInfo()
{
    while (g_aWitchInfo.Length)
    {
        UserVector uDamagerVector = g_aWitchInfo.Get(0, eDamagerInfoVector);
        delete uDamagerVector;

        g_aWitchInfo.Erase(0);
    }
}

// utilize our map g_smUserNames
bool GetClientNameFromUserId(int iUserId, char[] szClientName, int iMaxLen)
{
    if (iUserId == WORLD_INDEX)
    {
        FormatEx(szClientName, iMaxLen, "World");
        return true;
    }

    int iClient = GetClientOfUserId(iUserId);
    if (iClient && IsClientInGame(iClient)) {
        return GetClientNameFixed(iClient, szClientName, iMaxLen, 18);
    }

    char szKey[16];
    IntToString(iUserId, szKey, sizeof(szKey));
    return g_smUserNames.GetString(szKey, szClientName, iMaxLen);
}

int SortAdtDamageDesc(int iIdx1, int iIdx2, Handle hArray, Handle hHndl)
{
    UserVector uDamagerVector = view_as<UserVector>(hArray);
    int iDmg1 = uDamagerVector.Get(iIdx1, eDmgDone);
    int iDmg2 = uDamagerVector.Get(iIdx2, eDmgDone);
    if      (iDmg1 > iDmg2) return -1;
    else if (iDmg1 < iDmg2) return  1;
    return 0;
}

int GetDamageAsPercent(int iDmg, int iMaxHealth) {
    return RoundToFloor((float(iDmg) / iMaxHealth) * 100.0);
}

bool IsExactPercent(int iDmg, int iMaxHealth) {
    return (FloatAbs(float(GetDamageAsPercent(iDmg, iMaxHealth)) - ((float(iDmg) / iMaxHealth) * 100.0)) < 0.001) ? true : false;
}

bool IsEntityWitch(int iEnt)
{
    if (iEnt <= MaxClients || !IsValidEdict(iEnt) || !IsValidEntity(iEnt))
        return false;

    char szClsName[ENTITY_NAME_LENGTH];
    GetEdictClassname(iEnt, szClsName, sizeof(szClsName));

    // witch and witch_bride
    return (strncmp(szClsName, "witch", 5) == 0);
}

/**
 *
 */
bool GetClientNameFixed(int iClient, char[] szClientName, int iLength, int iMaxSize)
{
    if (!GetClientName(iClient, szClientName, iLength)) {
        return false;
    }

    if (strlen(szClientName) > iMaxSize)
    {
        szClientName[iMaxSize - 3] = szClientName[iMaxSize - 2] = szClientName[iMaxSize - 1] = '.';
        szClientName[iMaxSize] = '\0';
    }

    return true;
}

/**
 * Returns whether an entity is a player.
 */
bool IsValidClient(int iClient) {
    return (iClient > 0 && iClient <= MaxClients);
}

/**
 * Returns whether the player is survivor.
 */
bool IsClientSurvivor(int iClient) {
    return (IsClientInGame(iClient) && GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Returns whether the player is infected.
 */
bool IsClientInfected(int iClient) {
    return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client     Client index.
 * @return L4D1      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=WITCH, 5=TANK, 6=NOT INFECTED
 * @return L4D2      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetInfectedClass(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 *
 */
bool IsClientTank(int iClient) {
    return (GetInfectedClass(iClient) == SI_CLASS_TANK);
}
