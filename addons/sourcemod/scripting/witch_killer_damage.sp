#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdkhooks>
#include <colors>


public Plugin myinfo =
{
	name = "WitchKillerDamage",
	author = "TouchMe",
	description = "Print damage to Witch",
	version = "build0001",
	url = "https://github.com/TouchMe-Inc/l4d2_witch_killer_damage"
}


#define TRANSLATIONS            "witch_killer_damage.phrases"

/*
 * Infected Class.
 */
#define CLASS_TANK              8

/*
 * Team.
 */
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3


bool g_bRoundIsLive = false;

int
	g_iKillerDamage[MAXPLAYERS + 1] = {0, ...}, /*< Damage done to Witch, client tracking */
	g_iTotalDamage = 0 /*< Total Damage done to Witch. */
;

ConVar g_cvWitchHealth = null;


/**
 * Called before OnPluginStart.
 *
 * @param myself      Handle to the plugin
 * @param bLate       Whether or not the plugin was loaded "late" (after map load)
 * @param sErr        Error message buffer in case load failed
 * @param iErrLen     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure
 */
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
 * Called when the map starts loading.
 */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	g_cvWitchHealth = FindConVar("z_witch_health");

	// Events.
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("infected_hurt", Event_WitchHurt, EventHookMode_Post);
	HookEvent("witch_killed", Event_WitchDeath, EventHookMode_Post);
}

/**
 * Round start event.
 */
void Event_PlayerLeftStartArea(Event event, const char[] sName, bool bDontBroadcast)
{
	g_bRoundIsLive = true;

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		g_iKillerDamage[iClient] = 0;
	}

	g_iTotalDamage = 0;
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
	if (g_bRoundIsLive) {
		g_bRoundIsLive = false;
	}
}

public void Event_WitchHurt(Event event, const char[] name, bool bDontBroadcast)
{
	int iVictimEnt = GetEventInt(event, "entityid");

	if (!IsWitch(iVictimEnt)) {
		return;
	}

	int iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!IsValidClient(iAttacker) || !IsClientInGame(iAttacker) || !IsClientSurvivor(iAttacker)) {
		return;
	}

	int iDamage = GetEventInt(event, "amount");
	int iWitchHealth = GetEntProp(iVictimEnt, Prop_Data, "m_iHealth");
	int iDelta = iWitchHealth - iDamage;

	if (iDelta < 0) {
		iDamage += iDelta;
	}

	g_iKillerDamage[iAttacker] += iDamage;
	g_iTotalDamage += iDamage;
}

public void Event_WitchDeath(Event event, const char[] name, bool bDontBroadcast)
{
	int iKiller = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iKiller) || !IsClientInGame(iKiller)) {
		return;
	}

	/**
	 * Tank Killed the Witch.
	 */
	if (IsClientInfected(iKiller) && IsClientTank(iKiller))
	{
		for (int iClient = 1; iClient <= MaxClients; iClient ++)
		{
			if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
				continue;
			}

			PrintToChat(iClient, "%T%T", "TAG", iClient, "TANK_KILLER", iClient);
		}

		return;
	}

	else if (IsClientSurvivor(iKiller))
	{
		int iMaxHelath = RoundToFloor(GetConVarFloat(g_cvWitchHealth));

		if (g_iTotalDamage < iMaxHelath)
		{
			g_iKillerDamage[iKiller] += (iMaxHelath - g_iTotalDamage);
			g_iTotalDamage = iMaxHelath;
		}
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| !IsClientSurvivor(iPlayer)
		|| !g_iKillerDamage[iPlayer]) {
			continue;
		}

		iPlayers[iTotalPlayers ++] = iPlayer;
	}

	if (!iTotalPlayers) {
		return;
	}

	SortCustom1D(iPlayers, iTotalPlayers, SortDamage);

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
			continue;
		}

		PrintToChatDamage(iClient, iPlayers, iTotalPlayers);
	}
}

void PrintToChatDamage(int iClient, const int[] iPlayers, int iTotalPlayers)
{
	CPrintToChat(iClient, "%T%T", "BRACKET_START", iClient, "TAG", iClient);

	char sName[MAX_NAME_LENGTH];

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		int iPlayer = iPlayers[iItem];
		float fDamageProcent = 0.0;

		if (g_iTotalDamage > 0.0) {
			fDamageProcent = 100.0 * float(g_iKillerDamage[iPlayer]) / float(g_iTotalDamage);
		}

		GetClientNameFixed(iPlayer, sName, sizeof(sName), 18);

		CPrintToChat(iClient, "%T%T",
			(iItem + 1) == iTotalPlayers ? "BRACKET_END" : "BRACKET_MIDDLE", iClient,
			"SURVIVOR_KILLER", iClient,
			sName,
			g_iKillerDamage[iPlayer],
			fDamageProcent
		);
	}
}

bool IsWitch(int iEntity)
{
	if (iEntity > 0 && IsValidEntity(iEntity) && IsValidEdict(iEntity))
	{
		char strClassName[32];
		GetEdictClassname(iEntity, strClassName, sizeof(strClassName));

		return StrEqual(strClassName, "witch");
	}

	return false;
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

int SortDamage(int elem1, int elem2, const int[] array, Handle hndl)
{
	int iDamage1 = g_iKillerDamage[elem1];
	int iDamage2 = g_iKillerDamage[elem2];

	if (iDamage1 > iDamage2) {
		return -1;
	} else if (iDamage1 < iDamage2) {
		return 1;
	}

	return 0;
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client     Client index.
 * @return L4D1      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=WITCH, 5=TANK, 6=NOT INFECTED
 * @return L4D2      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetClientClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

bool IsClientTank(int iClient) {
	return (GetClientClass(iClient) == CLASS_TANK);
}

/**
 *
 */
void GetClientNameFixed(int iClient, char[] name, int length, int iMaxSize)
{
	GetClientName(iClient, name, length);

	if (strlen(name) > iMaxSize)
	{
		name[iMaxSize - 3] = name[iMaxSize - 2] = name[iMaxSize - 1] = '.';
		name[iMaxSize] = '\0';
	}
}
