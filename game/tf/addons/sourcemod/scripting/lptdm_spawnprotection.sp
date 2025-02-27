/**
 * Copyright Andrew Betson.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#include <tf2>
#include <tf2_stocks>
#include <tf2utils>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name		= "LPTDM - Spawn Protection",
	author		= "Andrew \"andrewb\" Betson",
	description	= "Configurable spawn protection plugin for LazyPurple's TDM Server.",
	version		= "1.2.0",
	url			= "https://www.github.com/AndrewBetson/TF-LPTDM"
};

bool	g_bIsPreGame;

bool	g_bIsClientProtected[ MAXPLAYERS + 1 ] = { false, ... };
bool	g_bShouldClientReceiveProtection[ MAXPLAYERS + 1 ] = { false, ... };
bool	g_bHasLeftSpawnroom[ MAXPLAYERS + 1 ] = { false, ... };

ConVar	sv_lptdm_spawnprotection_cancel_on_attack;
ConVar	sv_lptdm_spawnprotection_disable_during_pregame;
ConVar	sv_lptdm_spawnprotection_duration;

public void OnPluginStart()
{
	if ( GetEngineVersion() != Engine_TF2 )
	{
		SetFailState( "The LPTDM plugins are only compatible with Team Fortress 2." );
	}

	LoadTranslations( "lptdm.phrases" );
	AutoExecConfig( true, "lptdm_spawnprotection" );

	sv_lptdm_spawnprotection_cancel_on_attack = CreateConVar(
		"sv_lptdm_spawnprotection_cancel_on_attack",
		"0",
		"Cancel spawn protection when a player fires their weapon.",
		FCVAR_NONE,
		true, 0.0,
		true, 1.0
	);

	sv_lptdm_spawnprotection_disable_during_pregame = CreateConVar(
		"sv_lptdm_spawnprotection_disable_during_pregame",
		"1.0",
		"Disable spawn protection during pre-game warmup.",
		FCVAR_NONE,
		true, 0.0,
		true, 1.0
	);

	sv_lptdm_spawnprotection_duration = CreateConVar(
		"sv_lptdm_spawnprotection_duration",
		"5.0",
		"How long spawn protection should last.",
		FCVAR_NONE,
		true, 0.001
	);

	HookEvent( "player_spawn", Event_PlayerSpawn, EventHookMode_Post );
	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );

}

void Protection_Apply(int nClientIdx)
{
	TF2_AddCondition( nClientIdx, TFCond_Ubercharged, sv_lptdm_spawnprotection_duration.FloatValue );
	g_bIsClientProtected[ nClientIdx ] = true;
}

Action Event_PlayerSpawn( Handle hEvent, char[] szName, bool bDontBroadcast )
{
	if ( g_bIsPreGame && sv_lptdm_spawnprotection_disable_during_pregame.BoolValue )
	{
		return Plugin_Continue;
	}

	int nClientIdx = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	if ( !g_bShouldClientReceiveProtection[ nClientIdx ] )
	{
		return Plugin_Continue;
	}

	Protection_Apply(nClientIdx);
	g_bShouldClientReceiveProtection[ nClientIdx ] = false;

	return Plugin_Continue;
}

Action Event_PlayerDeath( Handle hEvent, char[] szName, bool bDontBroadcast )
{
	if ( g_bIsPreGame && sv_lptdm_spawnprotection_disable_during_pregame.BoolValue )
	{
		return Plugin_Continue;
	}

	int nClientIdx = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	g_bShouldClientReceiveProtection[ nClientIdx ] = true;
	g_bHasLeftSpawnroom[ nClientIdx ] = false;

	return Plugin_Continue;
}

public void OnMapStart()
{
	CreateTimer( 1.0, Timer_ExtendProtection, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE );
}

Action Timer_ExtendProtection(Handle hTimer)
{
	for ( int nClientIdx = 1; nClientIdx <= MaxClients; nClientIdx++ )
	{
		if ( IsClientInGame( nClientIdx ) && g_bIsClientProtected[ nClientIdx ] && !g_bHasLeftSpawnroom[ nClientIdx ] )
		{
			float vOrigin[3];
			GetClientAbsOrigin( nClientIdx, vOrigin );
			if ( TF2Util_IsPointInRespawnRoom( vOrigin, nClientIdx, true ) )
			{
				Protection_Apply( nClientIdx );
			}
			else
			{
				g_bHasLeftSpawnroom[ nClientIdx ] = true;
			}
		}
	}
	return Plugin_Continue;
}

public void OnMapEnd()
{
	for ( int i = 0; i < MAXPLAYERS + 1; i++ )
	{
		g_bIsClientProtected[ i ] = false;
		g_bShouldClientReceiveProtection[ i ] = false;
		g_bHasLeftSpawnroom[ i ] = false;
	}
}

public void OnClientConnected( int nClientIdx )
{
	if ( g_bIsPreGame && sv_lptdm_spawnprotection_disable_during_pregame.BoolValue )
	{
		return;
	}

	g_bShouldClientReceiveProtection[ nClientIdx ] = true;
}

public void OnClientDisconnect( int nClientIdx )
{
	g_bIsClientProtected[ nClientIdx ] = false;
	g_bShouldClientReceiveProtection[ nClientIdx ] = false;
	g_bHasLeftSpawnroom[ nClientIdx ] = false;
}

public void TF2_OnConditionRemoved( int nClientIdx, TFCond eCondition )
{
	if ( eCondition == TFCond_Ubercharged && g_bIsClientProtected[ nClientIdx ] )
	{
		g_bIsClientProtected[ nClientIdx ] = false;
	}
}

public void TF2_OnWaitingForPlayersStart()
{
	g_bIsPreGame = true;
}

public void TF2_OnWaitingForPlayersEnd()
{
	g_bIsPreGame = false;
}

public Action OnPlayerRunCmd(
	int nClientIdx, int &nButtonMask, int &nImpulse,
	float vDesiredVelocity[ 3 ], float vDesiredViewAngles[ 3 ],
	int &nWeapon, int &nSubtype,
	int &nCmdNum, int &nTickCount,
	int &nSeed, int vMousePos[ 2  ]
)
{
	if ( !sv_lptdm_spawnprotection_cancel_on_attack.BoolValue || !g_bIsClientProtected[ nClientIdx ] )
	{
		return Plugin_Continue;
	}

	bool bClientAttacked = view_as< bool >( nButtonMask & IN_ATTACK );
	if ( bClientAttacked )
	{
		TF2_RemoveCondition( nClientIdx, TFCond_Ubercharged );
	}

	return Plugin_Continue;
}
