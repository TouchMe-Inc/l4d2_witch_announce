#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdkhooks>
#include <colors>


public Plugin myinfo = {
	name = "WitchKillerDamage",
	author = "TouchMe",
	description = "Displays in chat the damage done to the witch",
	version = "build_0003",
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


enum struct WitchData
{
	int iEnt;
	int iNum;
	int iKillerDamage[MAXPLAYERS + 1]; /*< Damage done to Witch, client tracking */
	int iTotalDamage;                  /*< Total Damage done to Witch. */
	int iMaxHealth;
}

ConVar g_cvWitchHealth = null;

int g_iWitchNum = 0;

Handle g_hWitchList = null;

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
 *
 */
public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	g_cvWitchHealth = FindConVar("z_witch_health");

	// Events.
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("infected_hurt", Event_WitchHurt, EventHookMode_Post);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);

	g_hWitchList = CreateArray(sizeof(WitchData));
}

/**
 * Round end event.
 */
void Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast)
{
	g_iWitchNum = 0;
	ClearArray(g_hWitchList);
}

/**
 *
 */
public void OnEntityCreated(int iEnt, const char[] sClassName)
{
	if (iEnt > MaxClients && IsValidEntity(iEnt) && StrEqual(sClassName, "witch"))
	{
		WitchData eWitchData;
		eWitchData.iEnt = iEnt;
		eWitchData.iNum = ++ g_iWitchNum;

		for (int iClient = 1; iClient <= MaxClients; iClient ++)
		{
			eWitchData.iKillerDamage[iClient] = 0;
		}

		eWitchData.iTotalDamage = 0;
		eWitchData.iMaxHealth = RoundToFloor(GetConVarFloat(g_cvWitchHealth));

		PushArrayArray(g_hWitchList, eWitchData);
	}
}

/**
 *
 */
void Event_WitchHurt(Event event, const char[] sEventName, bool bDontBroadcast)
{
	int iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!iAttacker || !IsClientInGame(iAttacker) || !IsClientSurvivor(iAttacker)) {
		return;
	}

	int iVictimEnt = GetEventInt(event, "entityid");

	if (!IsWitch(iVictimEnt)) {
		return;
	}

	int iWitchIndex = FindWitchIndex(iVictimEnt);

	if (iWitchIndex == -1) {
		return;
	}

	int iDamage = GetEventInt(event, "amount");
	int iWitchHealth = GetEntProp(iVictimEnt, Prop_Data, "m_iHealth");
	int iDeltaHealth = iWitchHealth - iDamage;

	if (iDeltaHealth < 0) {
		iDamage += iDeltaHealth;
	}

	WitchData eWitchData;
	GetArrayArray(g_hWitchList, iWitchIndex, eWitchData);

	eWitchData.iKillerDamage[iAttacker] += iDamage;
	eWitchData.iTotalDamage += iDamage;

	SetArrayArray(g_hWitchList, iWitchIndex, eWitchData);
}

/**
 *
 */
void Event_WitchKilled(Event event, const char[] sEventName, bool bDontBroadcast)
{
	int iWitchEnt = GetEventInt(event, "witchid");

	int iWitchIndex = FindWitchIndex(iWitchEnt);

	if (iWitchIndex == -1) {
		return;
	}

	WitchData eWitchData;
	GetArrayArray(g_hWitchList, iWitchIndex, eWitchData);

	int iKiller = GetClientOfUserId(GetEventInt(event, "userid"));

	if (iKiller && IsClientInGame(iKiller))
	{
		/**
		 * Tank Killed the Witch.
		 */
		if (IsClientInfected(iKiller) && IsClientTank(iKiller))
		{
			CPrintToChatAll("%t%t", "TAG", "TANK_KILLER", eWitchData.iNum);
			return;
		}

		/**
		 * Survivor Killed the Witch.
		 */
		else if (IsClientSurvivor(iKiller))
		{
			if (eWitchData.iTotalDamage < eWitchData.iMaxHealth)
			{
				eWitchData.iKillerDamage[iKiller] += (eWitchData.iMaxHealth - eWitchData.iTotalDamage);
				eWitchData.iTotalDamage = eWitchData.iMaxHealth;

				SetArrayArray(g_hWitchList, iWitchIndex, eWitchData);
			}
		}
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| !IsClientSurvivor(iPlayer)
		|| !eWitchData.iKillerDamage[iPlayer]) {
			continue;
		}

		iPlayers[iTotalPlayers ++] = iPlayer;
	}

	if (!iTotalPlayers)
	{
		RemoveFromArray(g_hWitchList, iWitchIndex);
		return;
	}

	Handle hDataPack = CreateDataPack();
	WritePackCell(hDataPack, iWitchIndex);
	SortCustom1D(iPlayers, iTotalPlayers, SortDamage, hDataPack);
	CloseHandle(hDataPack);

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
			continue;
		}

		PrintToChatDamage(iClient, iWitchIndex, iPlayers, iTotalPlayers);
	}

	RemoveFromArray(g_hWitchList, iWitchIndex);
}

/**
 *
 */
void PrintToChatDamage(int iClient, int iWitchIndex, const int[] iPlayers, int iTotalPlayers)
{
	WitchData eWitchData;
	GetArrayArray(g_hWitchList, iWitchIndex, eWitchData);

	CPrintToChat(iClient, "%T%T%T", "BRACKET_START", iClient, "TAG", iClient, "INFO", iClient, eWitchData.iNum);

	char sName[MAX_NAME_LENGTH];

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		int iPlayer = iPlayers[iItem];
		float fDamageProcent = 100.0 * float(eWitchData.iKillerDamage[iPlayer]) / float(eWitchData.iMaxHealth);

		GetClientNameFixed(iPlayer, sName, sizeof(sName), 18);

		CPrintToChat(iClient, "%T%T",
			(iItem + 1) == iTotalPlayers ? "BRACKET_END" : "BRACKET_MIDDLE", iClient,
			"SURVIVOR_KILLER", iClient,
			sName,
			eWitchData.iKillerDamage[iPlayer],
			fDamageProcent
		);
	}
}

/**
 *
 */
int FindWitchIndex(int iWitchEnt)
{
	int iArraySize = GetArraySize(g_hWitchList);

	if (!iArraySize) {
		return -1;
	}

	int iWitchIndex = -1;

	WitchData eWitchData;

	for (int iIndex = 0; iIndex < iArraySize; iIndex ++)
	{
		GetArrayArray(g_hWitchList, iIndex, eWitchData);

		if (eWitchData.iEnt == iWitchEnt)
		{
			iWitchIndex = iIndex;
			break;
		}
	}

	return iWitchIndex;
}

/**
 *
 */
int SortDamage(int elem1, int elem2, const int[] array, Handle hndl)
{
	ResetPack(hndl);
	int iWitchIndex = ReadPackCell(hndl);

	WitchData eWitchData;
	GetArrayArray(g_hWitchList, iWitchIndex, eWitchData);

	int iDamage1 = eWitchData.iKillerDamage[elem1];
	int iDamage2 = eWitchData.iKillerDamage[elem2];

	if (iDamage1 > iDamage2) {
		return -1;
	} else if (iDamage1 < iDamage2) {
		return 1;
	}

	return 0;
}

/**
 * Returns whether the player is infected.
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Returns whether the player is survivor.
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

/**
 *
 */
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

/**
 *
 */
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
