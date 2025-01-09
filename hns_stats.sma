#include <amxmodx>
#include <hamsandwich>
#include <fakemeta>
#include <sqlx>

#define PLUGIN "Hide-and-Seek Statistic"
#define VERSION "release 1"
#define AUTHOR "Antarktida"

#define gPrefix "^3[Stats]"

#define SHOW_DEMO_RECORD_MSG
#define SHOW_PLAYER_RANK_ON_CONNECT

new const db_Host[] = "46.174.52.184";
new const db_Name[] = "PlayersInfo";
new const db_User[] = "admin";
new const db_Pass[] = "Krasivey2006";
new const table_name[] = "hns_players";

const SECONDS_LIVE_FOR_EXP = 10;
const EXP_FOR_KILL = 6;
const EXP_FOR_ASSIST = 3;
const Float:MIN_DMG_FOR_SAVE = 1.0;

enum _:SQL {
    SQL_TABLE,
    SQL_INFO,
    SQL_RANK,
    SQL_INSERT,
    SQL_SAVE 
};

enum _:PLAYER_INFO{
    pi_db_id,
    pi_IP[16],
    pi_STEAMID[32],
    pi_FirstName[32],
    pi_LastName[32],
    bool: loaded,
    pi_EXP,
    pi_EXPtop,
    pi_Kills,
    pi_DMG,
    Float:pi_now_Time,
    pi_Time
};

enum _:DAMAGE_INFO{
    Float:di_flDmg,
    Float:di_flDmgTime
};

new Handle: Database;

new g_Players[32][PLAYER_INFO];
new g_plDmg[32][DAMAGE_INFO];

new Float:g_aliveTimer[32];

public plugin_init(){
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterSql();

    // register_clcmd("say /help", "hns_helpCmd");
    // register_clcmd("say_team /help", "hns_helpCmd");

    register_clcmd("say", "hns_sayCmd");
    register_clcmd("say_team", "hns_sayCmd");

    register_event("InitHUD", "EventInitHUD", "b");

    RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage_Post", true);
    RegisterHam(Ham_Spawn, "player", "fwdSpawnPost", true);
    RegisterHam(Ham_Killed, "player", "fwd_PlayerKilled_Pre", 0);
}

public client_putinserver(id){
    arrayset(g_Players[id], 0, PLAYER_INFO);
    SQL_Info(id);
}

public EventInitHUD(id){
    if(is_user_bot(id) || is_user_hltv(id))
		return
	
    set_task(3.0, "show_info", id)
}

public show_info(id){
    client_print_color(id, print_team_red, "%s ^3This server is using ^4Hide-and-Seek stats^3", gPrefix, id);
    #if defined SHOW_DEMO_RECORD_MSG
    client_print_color(id, print_team_red, "%s ^3Hello, ^4%n^3! Demo recording started. GL & HF!", gPrefix, id);
    #endif
    #if defined SHOW_PLAYER_RANK_ON_CONNECT
    client_print_color(id, print_team_red, "%s ^3You are ranked ^4%dth^3 with ^4%d EXP^3 points", gPrefix, g_Players[id][pi_EXPtop], g_Players[id][pi_EXP]);
    #endif
}

public client_disconnected(id){
    if(!g_Players[id][loaded])
        return;

    SQL_Save(id);
}

public hns_sayCmd(id){
    new szBuffer[64];
    read_args(szBuffer, charsmax(szBuffer));
    remove_quotes(szBuffer);
    
    if(szBuffer[0] == '/'){
        new szCmd[8], szName[32]; 
        parse(szBuffer, szCmd, charsmax(szCmd), szName, charsmax(szName));
        if  (!(equali(szCmd, "/name") || equali(szCmd, "/dmg") \
            || equali(szCmd, "/time") || equali(szCmd, "/exp") \
            || equali(szCmd, "/kills")))
             return PLUGIN_CONTINUE;

        new index = szName[0] ? find_player_ex(FindPlayer_MatchNameSubstring|FindPlayer_CaseInsensitive, szName) : id;
        if(!index){
                client_print_color(id, print_team_default, "%s ^3You need to clarify, multiply players have pattern -> ^4%s^3", gPrefix, szName);
                return PLUGIN_CONTINUE;
        }

        if(equali(szCmd, "/name")){
            client_print_color(0, print_team_red, "%s ^3Player ^4%n^3", gPrefix, index);
            client_print_color(0, print_team_red, "%s ^3First name - ^4%s^3", gPrefix, g_Players[index][pi_FirstName]);
            client_print_color(0, print_team_red, "%s ^3Last name - ^4%s^3", gPrefix, g_Players[index][pi_LastName]);

        } else if(equali(szCmd, "/dmg")){
            if(g_plDmg[index][di_flDmg])
                client_print_color(0, print_team_red, "%s ^4%n's^3 fall damage ^4%.0f^3 HP ^4%.1f^3 seconds ago", gPrefix, index, g_plDmg[index][di_flDmg], get_gametime() - g_plDmg[index][di_flDmgTime]);

            client_print_color(0, print_team_red, "%s ^3Total damage - ^4%d HP^3", gPrefix, g_Players[index][pi_DMG]);
        }
        else if(equali(szCmd, "/time"))
            client_print_color(0, print_team_red, "%s ^4%n's^3 playtime is ^4%d minutes^3", gPrefix, index, (floatround(get_gametime() - g_Players[index][pi_now_Time]) + g_Players[index][pi_Time]) / 60);
        else if(equali(szCmd, "/exp"))
            client_print_color(0, print_team_red, "%s ^4%n^3 has ^4%d EXP^3 and takes ^4%d place^3", gPrefix, index, g_Players[index][pi_EXP], g_Players[index][pi_EXPtop]);
        else if(equali(szCmd, "/kills"))
            client_print_color(0, print_team_red, "%s ^4%n^3 caught up with the hiders ^4%d times^3", gPrefix, index, g_Players[index][pi_Kills]);

        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public OnPlayerTakeDamage_Post(victim, inflictor, attacker, Float:damage, damagebits) {
    g_Players[victim][pi_DMG] += floatround(damage);
    if(~damagebits & DMG_FALL || damage < MIN_DMG_FOR_SAVE){
        if(get_user_team(attacker) == 2 && get_user_team(victim) == 1){
            if(get_user_health(victim) > 0){ //TODO: переделать, не работает(is_user_alive(id)?)
                g_Players[attacker][pi_EXP] += EXP_FOR_ASSIST;
            } else { 
                g_Players[attacker][pi_EXP] += EXP_FOR_KILL;
                g_Players[attacker][pi_Kills]++;
            }
        }
    }
    g_plDmg[victim][di_flDmg] = damage;
    g_plDmg[victim][di_flDmgTime] = get_gametime();

}

public fwdSpawnPost(id){
    if(!is_user_alive(id)) return;

    if(get_user_team(id) == 1)
        g_aliveTimer[id] = get_gametime();
}

public fwd_PlayerKilled_Pre(id){
    if(get_user_team(id) == 1)
        g_Players[id][pi_EXP] += floatround(get_gametime() - g_aliveTimer[id]) / SECONDS_LIVE_FOR_EXP;
}

RegisterSql(){
    Database = SQL_MakeDbTuple(db_Host, db_User, db_Pass, db_Name);
    SQL_SetCharset(Database, "utf-8");

    new Query[512];
    new data[1] = SQL_TABLE;
    formatex(Query, charsmax(Query), "\
        CREATE TABLE IF NOT EXISTS `%s` ( \
			`id`         INT(11) NOT NULL auto_increment PRIMARY KEY, \
            `ip`         VARCHAR(16) NULL DEFAULT NULL, \
			`steamid`    VARCHAR(32) NULL DEFAULT NULL, \
            `firstname`  VARCHAR(32) NULL DEFAULT NULL, \
			`lastname`   VARCHAR(32) NULL DEFAULT NULL, \
            `experience` INT(11) NOT NULL DEFAULT 0,    \
            `kills`      INT(11) NOT NULL DEFAULT 0,    \
            `damage`     INT(11) NOT NULL DEFAULT 0,    \
            `time`       INT(11) NOT NULL DEFAULT 0     \
        );", table_name);
    SQL_ThreadQuery(Database, "QueryHandler", Query, data, sizeof(data));
}

public QueryHandler(iFailState, Handle:hQuery, szError[], iErrNum, cData[], iSize, Float:fQueueTime){
    if(iFailState != TQUERY_SUCCESS){
        log_amx("Sql error: error %d - %s", iErrNum, szError);
        return;
    }

    switch(cData[0]){
        case SQL_INFO:{
            new id = cData[1];
            
            if(!is_user_connected(id)){
                return;
            }

            g_Players[id][pi_now_Time] = get_gametime();

            if(SQL_NumResults(hQuery)){
                new index = SQL_FieldNameToNum(hQuery, "id");
                new ip_index = SQL_FieldNameToNum(hQuery, "ip");
                new steamid_index = SQL_FieldNameToNum(hQuery, "steamid");
                new first_name_index = SQL_FieldNameToNum(hQuery, "firstname");
                new last_name_index = SQL_FieldNameToNum(hQuery, "lastname");
                new exp_index = SQL_FieldNameToNum(hQuery, "experience");
                new kills_index = SQL_FieldNameToNum(hQuery, "kills");
                new dmg_index = SQL_FieldNameToNum(hQuery, "damage");
                new time_index = SQL_FieldNameToNum(hQuery, "time");

                g_Players[id][pi_db_id] = SQL_ReadResult(hQuery, index);
                SQL_ReadResult(hQuery, ip_index, g_Players[id][pi_IP], charsmax(g_Players[][pi_IP]));
                SQL_ReadResult(hQuery, steamid_index, g_Players[id][pi_STEAMID], charsmax(g_Players[][pi_STEAMID]));
                SQL_ReadResult(hQuery, first_name_index, g_Players[id][pi_FirstName], charsmax(g_Players[][pi_FirstName]));
                SQL_ReadResult(hQuery, last_name_index, g_Players[id][pi_LastName], charsmax(g_Players[][pi_LastName]));
                g_Players[id][pi_EXP] = SQL_ReadResult(hQuery, exp_index);
                g_Players[id][pi_Kills] = SQL_ReadResult(hQuery, kills_index);
                g_Players[id][pi_DMG] = SQL_ReadResult(hQuery, dmg_index);
                g_Players[id][pi_Time] = SQL_ReadResult(hQuery, time_index);
                g_Players[id][loaded] = true;

                SQL_Rank(id);
            } else {
                SQL_Insert(id);
                get_user_name(id, g_Players[id][pi_FirstName], charsmax(g_Players[][pi_FirstName]));
            }
        }

        case SQL_RANK:{
            new id = cData[1];
            if(!is_user_connected(id)) return;

            if(SQL_NumResults(hQuery))
                g_Players[id][pi_EXPtop] = SQL_ReadResult(hQuery, 0);
        }

        case SQL_INSERT:{
            new index = SQL_GetInsertId(hQuery);
            new id = cData[1];

            g_Players[id][pi_db_id] = index;
            g_Players[id][loaded] = true;

            SQL_Rank(id);
        }

        case SQL_SAVE: {}
    }
}

public SQL_Info(id){
    new szQuery[256];
    new szAuthId[32]; get_user_authid(id, szAuthId, charsmax(szAuthId));
    new cData[2]; cData[0] = SQL_INFO, cData[1] = id;
    formatex(szQuery, charsmax(szQuery), "\
        SELECT * \
		FROM `%s` \
		WHERE `steamid` = '%s'", table_name, szAuthId);
    SQL_ThreadQuery(Database, "QueryHandler", szQuery, cData, sizeof(cData));
}

SQL_Rank(id){
    new szQuery[256], cData[2];
    cData[0] = SQL_RANK; cData[1] = id;

    new szAuthId[32]; get_user_authid(id, szAuthId, charsmax(szAuthId));

    formatex(szQuery, charsmax(szQuery), "\
		SELECT COUNT(*) \
		FROM `%s` \
		WHERE `experience` >= %d", table_name, g_Players[id][pi_EXP]);
    SQL_ThreadQuery(Database, "QueryHandler", szQuery, cData, sizeof(cData));
}

public SQL_Insert(id){
    new Query[512];
    new cData[2]; cData[0] = SQL_INSERT, cData[1] = id;

    new szName[64]; SQL_QuoteString(Empty_Handle, szName, charsmax(szName), fmt("%n", id));
    new szAuthId[32]; get_user_authid(id, szAuthId, charsmax(szAuthId));
    new szIP[16]; get_user_ip(id, szIP, charsmax(szIP));

    trim_before(szIP);
    formatex(Query, charsmax(Query), "\
    INSERT INTO `%s` \
        ( \
            ip,        \
            steamid,   \
            firstname  \
        ) \
        VALUES \
        ( \
            '%s', \
            '%s', \
            '%s'  \
        );", table_name, szIP, szAuthId, szName);
    SQL_ThreadQuery(Database, "QueryHandler", Query, cData, sizeof(cData));
}

public SQL_Save(id){
    new Query[512];
    new cData[1] = SQL_SAVE;
    new szName[64]; SQL_QuoteString(Empty_Handle, szName, charsmax(szName), fmt("%n", id));
    new szAuthId[32]; get_user_authid(id, szAuthId, charsmax(szAuthId));

    formatex(Query, charsmax(Query), "\
        UPDATE `%s`                \
        SET                        \
        `lastname`   = '%s',       \
        `experience` =  %d,        \
        `kills`      =  %d,        \
        `damage`     =  %d,        \
        `time`       = `time` + %d \
        WHERE                      \
        `steamid`    = '%s'",      \
        table_name, szName, g_Players[id][pi_EXP], \
        g_Players[id][pi_Kills], g_Players[id][pi_DMG], \
        floatround(get_gametime() - g_Players[id][pi_now_Time]), szAuthId);
    SQL_ThreadQuery(Database, "QueryHandler", Query, cData, sizeof(cData));
}

trim_before(text[]){
    for(new i; text[i]; i++){
        if(text[i] == ':'){
            text[i] = 0;
            break;
        }
    }
}