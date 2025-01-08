#include <amxmodx>
#include <hamsandwich>
#include <engine>
#include <fakemeta>
#include <fun>
#include <reapi>

#define PLUGIN "Hide-and-Seek Public"
#define VERSION "release 1"
#define AUTHOR "Antarktida"
#define gPrefix "^3[Main]"
#define ACCESS ADMIN_KICK


new g_iRegisterSpawn;
new g_AddFlashNum, g_AddSmokeNum, g_AddHeNum, g_FlashNum, g_SmokeNum;
new bool: g_bSwapNextRound = false, g_bAddGrenades, g_bHideKnife[32] = { true, ... };

const SPEC = 3;
const CT = 2;
const TT = 1;

new const g_szDefaultEntities[][] = {
    "func_hostage_rescue",
    "info_hostage_rescue",
    "func_bomb_target",
    "info_bomb_target",
    "hostage_entity",
    "info_vip_start",
    "func_vip_safetyzone",
    "func_escapezone",
    "armoury_entity",
    "monster_scentist"
};

enum {
    e_mPub,
    e_mDuel
}

enum _:CvarPointers{
    cp_RoundOver,
    cp_AutoJoinTeam,
    cp_ShowRadioIcon
}

public plugin_precache(){
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_iRegisterSpawn = register_forward(FM_Spawn, "fwdSpawn", 1);

    new Cvars[CvarPointers];

    Cvars[cp_RoundOver] = get_cvar_pointer("mp_roundover");
    Cvars[cp_AutoJoinTeam] = get_cvar_pointer("mp_auto_join_team");
    Cvars[cp_ShowRadioIcon] = get_cvar_pointer("mp_show_radioicon");

    set_pcvar_num(Cvars[cp_RoundOver], 2);
    set_pcvar_num(Cvars[cp_AutoJoinTeam], 1);
    set_pcvar_num(Cvars[cp_ShowRadioIcon], 0);
}

public plugin_init(){
    g_FlashNum = register_cvar("hns_flash", "1");
    g_SmokeNum = register_cvar("hns_smoke", "1");
    g_AddFlashNum = register_cvar("hns_addflash", "1");
    g_AddSmokeNum = register_cvar("hns_addSmoke", "1");
    g_AddHeNum = register_cvar("hns_addHe", "0");
    g_bAddGrenades = register_cvar("hns_addGrenades", "1");
    
    register_clcmd("say", "hns_chat_manager");
    register_clcmd("say_team", "hns_chat_manager");

    register_clcmd( "chooseteam", "hns_block_cmd" );
    register_clcmd( "jointeam", "hns_block_cmd" );
    register_clcmd( "joinclass", "hns_block_cmd" );

    registerSayCmd("hideknife", "knife", "hns_hideknife");
    registerSayCmd("tt", "t", "hns_to_tt");
    registerSayCmd("spec", "back", "hns_switch_spec");
    registerSayCmd("restart", "rr", "hns_restart_round", ACCESS);
    registerSayCmd("swap", "sw", "hns_swap_teams", ACCESS);

    unregister_forward(FM_Spawn, g_iRegisterSpawn, 1);

    RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "fwdKnifePrim");
    RegisterHam(Ham_Item_Deploy, "weapon_knife", "fwdBlockKnife", 1);
    RegisterHam(Ham_Spawn, "player", "fwdSpawnPost", true);
    RegisterHam(Ham_Killed, "player", "fwd_PlayerKilled_Pre", 0);

    RegisterHookChain(RG_PlayerBlind, "PlayerBlind", false);
    RegisterHookChain(RG_CBasePlayer_ResetMaxSpeed, "CBasePlayer_ResetMaxSpeed_Pre", false);

    register_logevent("eventRoundEnd", 2, "0=World triggered", "1=Round_Draw", "1=Round_End");
}

public hns_hideknife(id){
    if(is_user_connected(id)){
        if(g_bHideKnife[id]){
            entity_set_string(id, EV_SZ_viewmodel, "");
            g_bHideKnife[id] = false;
            client_print_color(id, print_team_blue, "%s ^3Knife for you is ^4hidden", gPrefix);

        } else {
            entity_set_string(id, EV_SZ_viewmodel, "models/v_knife.mdl");
            g_bHideKnife[id] = true;
            client_print_color(id, print_team_blue, "%s ^3Knife for you is ^4visible", gPrefix);
        }
    }
}

public hns_to_tt(id){
    if(is_user_connected(id)){
        if(get_playersnum() == 1 && get_user_team(id) != TT){
            rg_set_user_team(id, TT);
            rg_round_respawn(id);
        }
    }
}

public hns_switch_spec(id){
    if(is_user_connected(id)){
        new team = get_user_team(id)
        switch (team){
            case CT, TT:{
                if(is_user_alive(id))
                    user_silentkill(id);

                rg_set_user_team(id, SPEC);
                set_entvar(id, var_solid, SOLID_NOT);
                set_entvar(id, var_movetype, MOVETYPE_FLY);
            }

            case SPEC:{
                rg_set_user_team(id, CT);
                rg_round_respawn(id);
            }
        }
    }
}

public hns_chat_manager(id){
    if (!is_user_connected(id)) {
        return PLUGIN_HANDLED;
    }
    
    new message[128];
    
    read_argv(0, message, charsmax(message));
    read_args(message, charsmax(message));
    remove_quotes(message);
    trim(message);

    if(message[0] == '/') {
        return PLUGIN_HANDLED_MAIN;
    }

    return PLUGIN_CONTINUE;
}

public setRole(id){
    new team = get_user_team(id);
    strip_user_weapons(id);
    set_user_footsteps(id, team == CT ? 0 : 1);

    if(team == TT){ rg_reset_maxspeed(id); }

    switch(team){
        case CT:{
            rg_give_item(id, "weapon_knife");
        }

        case TT:{
            rg_give_item(id, "weapon_knife");
            if(get_pcvar_num(g_FlashNum) >= 1){
                rg_give_item(id, "weapon_flashbang");
                rg_set_user_bpammo(id, WEAPON_FLASHBANG, get_pcvar_num(g_FlashNum));
            }

            if(get_pcvar_num(g_SmokeNum) >= 1){
                rg_give_item(id, "weapon_smokegrenade");
                rg_set_user_bpammo(id, WEAPON_SMOKEGRENADE, get_pcvar_num(g_SmokeNum));
            }
        }
    }
}

public hns_restart_round(){
    rg_round_end(0.5, WINSTATUS_DRAW, ROUND_END_DRAW, "Round Restarted", "none");
}

public hns_swap_teams(){
    swapAll();
}

public PlayerBlind(const index, const inflictor, const attacker, const Float:fadeTime, const Float:fadeHold, const alpha, Float:color[3])
{
	if(get_user_team(index) == TT || get_user_team(index) == SPEC)
		return HC_SUPERCEDE;

	return HC_CONTINUE;
}

public CBasePlayer_ResetMaxSpeed_Pre(id){
    if(get_user_team(id) == TT){
		set_entvar(id, var_maxspeed, 250.0);
		return HC_SUPERCEDE;
	}

    return HC_CONTINUE;
}

public fwdSpawn(entid){
    static szClassName[32];
    if(pev_valid(entid)){
        pev(entid, pev_classname, szClassName, 31);

        for(new i = 0; i < sizeof g_szDefaultEntities; i++){
            if(equal(szClassName, g_szDefaultEntities[i])){
                engfunc(EngFunc_RemoveEntity, entid);
                break;
            }
        }
    }
}

public fwdKnifePrim(const iPlayer){
    ExecuteHamB(Ham_Weapon_SecondaryAttack, iPlayer);
    return HAM_SUPERCEDE;
}

public fwdSpawnPost(id){
    if(!is_user_alive(id))
        return;

    setRole(id);
    hide_money(id);
}

public fwd_PlayerKilled_Pre( id ){
	if( get_user_team(id) != TT )
		return;
		
	if(g_bAddGrenades){
        new players[32], num, id;
        get_players(players, num, "ace", "TERRORIST");
        if( num == 1 ){
            id = players[0];
            rg_set_user_bpammo(id, WEAPON_HEGRENADE, get_pcvar_num(g_AddHeNum));
            rg_set_user_bpammo(id, WEAPON_FLASHBANG, get_pcvar_num(g_AddFlashNum));
            rg_set_user_bpammo(id, WEAPON_SMOKEGRENADE, get_pcvar_num(g_AddSmokeNum));
        }
    }
}

public fwdBlockKnife(const iEntity){
    new iClient = get_pdata_cbase(iEntity, 41, 4);

    if(get_user_team(iClient) == TT){
        entity_set_string(iClient, EV_SZ_viewmodel, "models/v_knife.mdl")
        set_pdata_float(iEntity, 46, 9999.0, 4);
        set_pdata_float(iEntity, 47, 9999.0, 4);
    }
    return HAM_IGNORED;
}

public eventRoundEnd(){
    new iPlayers[ 32 ], iNum;
    get_players(iPlayers, iNum, "ae", "TERRORIST");

    if(!iNum || g_bSwapNextRound){
        g_bSwapNextRound = false;
        swapAll();
    } else {
        g_bSwapNextRound = true;
    }
}

public hns_block_cmd(){
    return PLUGIN_HANDLED;
}

public hide_money(id){
    message_begin(MSG_ONE, 94, _, id);
    write_byte(1<<5);
    message_end();

    message_begin(MSG_ONE, 110, _, id);
    write_byte(0);
    message_end();
}

swapAll(){
    rg_swap_all_players();
}

stock registerSayCmd(const szCmd[], const szShort[], const szFunc[], flags = -1, szInfo[] = "")
{
	new szTemp[65], szInfoLang[65];
	format(szInfoLang, 64, "%L", LANG_SERVER, szInfo);

	format(szTemp, 64, "say /%s", szCmd);
	register_clcmd(szTemp, szFunc, flags, szInfoLang);
	
	format(szTemp, 64, "say .%s", szCmd);
	register_clcmd(szTemp, szFunc, flags, szInfoLang);

	format(szTemp, 64, "say /%s", szShort);
	register_clcmd(szTemp, szFunc, flags, szInfoLang);
	
	format(szTemp, 64, "say .%s", szShort);
	register_clcmd(szTemp, szFunc, flags, szInfoLang);

	return 1;
}