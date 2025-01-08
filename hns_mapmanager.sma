#include <amxmodx>

#define PLUGIN "Hide-and-Seek Map Manager"
#define VERSION "release 1"
#define AUTHOR "Antarktida"

#define gPrefix "^3[MapManager]"
#define gYourMapNominatedPrefix "[You]\d"
#define gMapNominatedPrefix "[\r%n\w]\d"
// #define gFormatDate "%d.%m.%Y"
// #define gFormatTime "%H:%M:%S"

const MIN_DENOMINATE_TIME = 5; // the time between denominating maps
const MAX_NOMINATED_MAPS_FOR_PLAYER = 2; // the max number nominated maps for person
const MAX_NOMINATED_MAPS = 5; // the maps count on vote without current map
const MIN_CHARS_COUNT_FOR_NOMINATING = 4; // the min chars count needed for start searching map
const MINUTES_TO_START_VOTE_BEFORE_END = 2;
const DEFAULT_TIMELIMIT = 20; 
const VOTE_TIME = 10; // the seconds to voting
const Float:PERCENT_OF_VOTED_PLAYERS = 60.0; // how many percent of voted players needed to start voting

const TASK_TIMER = 5555;

enum _:NOMINATEDMAP_INFO
{
	n_MapName[32],
	n_Player,
	n_MapIndex
};

enum _:VOTEDMAP_INFO
{
    v_MapName[32],
    v_VotesCount
};

new g_cvTimelimitPointer;

new g_iVoteTime;

new g_szCurrentMap[32]; // the name of current map
new g_szNextMap[32]; // the name of next map

new g_iNominatedMapsCount[32]; // the nominated maps count
new g_iLastTimeOfDenominate[32]; // the last time of player denominating map
new Array: g_arrNominatedMaps; // the nominated maps {"map name", "player id", "map id"}
new Array: g_arrMaps; // the all maps

new g_bIsPlayerVoted[32];
new g_matrixMapsOnVote[MAX_NOMINATED_MAPS + 1][VOTEDMAP_INFO];
new g_iVotes;
new g_iFinalVotes;
new g_iVotesNeeded;
new g_bVoteStarted;
new g_bVoteFinished;

public plugin_precache(){
    register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_init(){

    g_cvTimelimitPointer = get_cvar_pointer("mp_timelimit");

    register_clcmd("say thetime", "hns_thetime");
    register_clcmd("say timeleft", "hns_timeleft");
    register_clcmd("say nextmap", "hns_nextmap");
    register_clcmd("say currentmap", "hns_currentmap");

    register_clcmd("say", "hns_sayCmd");
    register_clcmd("say_team", "hns_sayCmd");

    register_clcmd("say /maps", "hns_showMapsList");
    register_clcmd("say_team /maps", "hns_showMapsList");

    register_clcmd("say /rtv", "hns_rockthevote");
    register_clcmd("say_team /rtv", "hns_rockthevote");
    register_clcmd("say rtv", "hns_rockthevote");
    register_clcmd("say_team rtv", "hns_rockthevote");

    g_bVoteStarted = false;
    g_bVoteFinished = false;

    g_iVotes = 0;

    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

    set_task(10.0, "Task_CheckTime", 100, .flags = "b");
}

public plugin_cfg(){
    g_arrNominatedMaps = ArrayCreate(NOMINATEDMAP_INFO);
    g_arrMaps = ArrayCreate(32);
    LoadMapsFromFile();
}

public client_disconnected(id){
    if(g_bIsPlayerVoted[id]){
        g_bIsPlayerVoted[id] = false;
        g_iVotes--;
    }
}

LoadMapsFromFile(){
    new szDir[128], szFile[128];	
    get_mapname(g_szCurrentMap, charsmax(g_szCurrentMap));

    get_localinfo("amxx_configsdir", szDir, charsmax(szDir));
    formatex(szFile, charsmax(szFile), "%s/maps.ini", szDir);

    if(file_exists(szFile)){
        new f = fopen(szFile, "rt");
        if(f){
            new szText[32], szMap[32];
            while(!feof(f)){
                fgets(f, szText, charsmax(szText));
                parse(szText, szMap, charsmax(szMap));

                if(!szMap[0] || szMap[0] == ';' || !is_map_valid(szMap) || get_map_index(szMap) || equali(szMap, g_szCurrentMap)) continue;
 
                ArrayPushString(g_arrMaps, szMap);
            }
            fclose(f);

            new size = ArraySize(g_arrMaps);
            if(size == 0)
                server_print("Nothing loaded from file!");


        }
    } else {
        server_print("Maps file doesn't exist.");
    }
}

public Event_NewRound(){
    if(g_bVoteStarted) return;

    if(g_bVoteFinished){
        client_print_color(0, print_team_blue, "%s ^3The next map is ^4%s", gPrefix, g_szNextMap);
        server_cmd("changelevel %s", g_szNextMap);
    }
}

public Task_CheckTime(){
    if(g_bVoteStarted || g_bVoteFinished) return PLUGIN_CONTINUE;

    new iTime = get_timeleft();
    if(iTime <= floatround(MINUTES_TO_START_VOTE_BEFORE_END * 60.0))
        StartVote();

    return PLUGIN_CONTINUE;
}

public hns_sayCmd(id){
    if(g_bVoteStarted || g_bVoteFinished) return;

    new szSayText[32]; read_args(szSayText, charsmax(szSayText));
    remove_quotes(szSayText); trim(szSayText); strtolower(szSayText);

    new target_index = get_map_index(szSayText);

    if(target_index){
        NominateMap(id, szSayText, target_index - 1);
    } else if(strlen(szSayText) >= MIN_CHARS_COUNT_FOR_NOMINATING){
        new Array: nomList = ArrayCreate(), nomListSize;
        target_index = 0
        while((target_index = find_map_by_subname(target_index, szSayText))){
            ArrayPushCell(nomList, target_index - 1);
            nomListSize++;
        }

        if(nomListSize == 1){
            target_index = ArrayGetCell(nomList, 0);
            new map[32]; ArrayGetArray(g_arrMaps, target_index, map);
            NominateMap(id, map, target_index);
        } else if(nomListSize > 1){
            ShowNominationList(id, nomList, nomListSize);
        }
        ArrayDestroy(nomList);
    }
}

public hns_showMapsList(id){
    new menu = menu_create("Choose map", "MapsList_handler");
    new mapName[32], szString[32], size = ArraySize(g_arrMaps);
    
    for(new i, nominated_index; i < size; i++){
        ArrayGetString(g_arrMaps, i, mapName, charsmax(mapName));
        nominated_index = is_map_nominated(i);

        if(nominated_index){
            new nomInfo[NOMINATEDMAP_INFO]; ArrayGetArray(g_arrNominatedMaps, i, nomInfo);
            if(id == nomInfo[n_Player]){
                formatex(szString, charsmax(szString), "%s %s", gYourMapNominatedPrefix, nomInfo[n_MapName]);
                menu_additem(menu, szString);
            } else {
                formatex(szString, charsmax(szString), "%s %s", gMapNominatedPrefix, nomInfo[n_Player], nomInfo[n_MapName]);
                menu_additem(menu, szString, _, (1 << 31));
            }
        } else {
            menu_additem(menu, mapName);
        }
    }

    menu_setprop(menu, MPROP_BACKNAME, "Back");
    menu_setprop(menu, MPROP_NEXTNAME, "Next");
    menu_setprop(menu, MPROP_EXITNAME, "Exit");

    menu_display(id, menu);
}

public MapsList_handler(id, menu, item){
    if(item == MENU_EXIT){
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[2], szName[32], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)

    new map_index = item;
    trim_after_space(szName, strlen(gYourMapNominatedPrefix));
    new is_map_nominate = NominateMap(id, szName, map_index);

    if(is_map_nominate == 1){
        new szString[48]; formatex(szString, charsmax(szString), "%s %s", gYourMapNominatedPrefix, szName);
        menu_item_setname(menu, item, szString);
    } else if(is_map_nominate == 2){
        menu_item_setname(menu, item, szName);
    }
    menu_display(id, menu);
    
    return PLUGIN_HANDLED;
}

public ShowNominationList(id, Array: array, size){
    new menu = menu_create("Choose map", "NominationList_handler");
    new mapName[32], szString[32], map_index, nominated_index; 
    for(new i, szNum[8]; i < size; i++){
        map_index = ArrayGetCell(array, i);
        ArrayGetString(g_arrMaps, map_index, mapName, charsmax(mapName));

        num_to_str(map_index, szNum, charsmax(szNum));
        nominated_index = is_map_nominated(map_index);

        if(nominated_index){
            new nomInfo[NOMINATEDMAP_INFO]; ArrayGetArray(g_arrNominatedMaps, nominated_index - 1, nomInfo);
            if(id == nomInfo[n_Player]){
                formatex(szString, charsmax(szString), "%s %s", gYourMapNominatedPrefix, nomInfo[n_MapName]);
                menu_additem(menu, szString, szNum);
            } else {
                formatex(szString, charsmax(szString), "%s %s", gMapNominatedPrefix, nomInfo[n_Player], nomInfo[n_MapName]);
                menu_additem(menu, szString, szNum, (1 << 31));
            }
        } else {
            menu_additem(menu, mapName, szNum);
        }
    }

    menu_setprop(menu, MPROP_BACKNAME, "Back");
    menu_setprop(menu, MPROP_NEXTNAME, "Next");
    menu_setprop(menu, MPROP_EXITNAME, "Exit");

    menu_display(id, menu);
}

public NominationList_handler(id, menu, item){
    if(item == MENU_EXIT){
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[8], szName[32], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);

    new map_index = str_to_num(szData);
    trim_after_space(szName, strlen(gYourMapNominatedPrefix));

    new is_map_nominate = NominateMap(id, szName, map_index);

    if(is_map_nominate == 1){
        new szString[48]; formatex(szString, charsmax(szString), "%s %s", gYourMapNominatedPrefix, szName);
        menu_item_setname(menu, item, szString);
        menu_display(id, menu);
    } else if(is_map_nominate == 2){
        menu_item_setname(menu, item, szName);
        menu_display(id, menu);
    } else {
		menu_destroy(menu);
	}

    return PLUGIN_HANDLED;
}

public hns_rockthevote(id){
    if(g_bVoteStarted || g_bVoteFinished)
        return;

    if(!g_bIsPlayerVoted[id]){
        g_bIsPlayerVoted[id] = true;
        g_iVotes++;
        if(CheckVotes()){
            client_print_color(0, print_team_blue, "%s ^3Player ^4%n^3 want to change map. Vote starting...", gPrefix, id);
            return;
        }
        client_print_color(0, print_team_blue, "%s ^3Player ^4%n^3 want to change map. Need ^3+%i^1 to start voting!", gPrefix, id, g_iVotesNeeded - g_iVotes);
    } else {
        g_bIsPlayerVoted[id] = false;
        g_iVotes--;
        client_print_color(0, print_team_blue, "%s ^3Player ^4%n^3 don't want to change map. Now you need ^4%i^3 to start voting!", gPrefix, id, g_iVotesNeeded - g_iVotes);
    }
}

public show_RockTheVoteMenu(Array: maps, size){
    new menu = menu_create("Vote for map", "RockTheVote_handler");

    new iPlayers[32], iNum; get_players(iPlayers, iNum, "ch");
    new mapName[32], num[4];

    for(new i; i < size; i++){
        ArrayGetString(maps, i, mapName, charsmax(mapName));
        num_to_str(i + 1, num, charsmax(num));
        formatex(g_matrixMapsOnVote[i][v_MapName], charsmax(g_matrixMapsOnVote[][v_MapName]), mapName);

        new item[32];
        if(i == (size - 2))
            formatex(item, charsmax(item), "%s", sum_strings(mapName, "^n"));
        else if (i == size - 1)
            formatex(item, charsmax(item), "%s", sum_strings("[\rExtend\w] ", mapName));
        else
            formatex(item, charsmax(item), "%s", mapName);

        menu_additem(menu, item, num);
    }

    for(new id, i; i < iNum; i++){
        id = iPlayers[i];
        menu_display(id, menu);
    }
}

public RockTheVote_handler(id, menu, item){
    if(g_bVoteFinished) return PLUGIN_HANDLED;
    new szNum[4], szName[32], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szNum, charsmax(szNum), szName, charsmax(szName), iCallback);

    new iKey = str_to_num(szNum) - 1;
    g_matrixMapsOnVote[iKey][v_VotesCount]++;
    g_iFinalVotes++;

    if(g_iFinalVotes == get_playersnum()){
        remove_task(TASK_TIMER);
        FinishVote();
    }

    return PLUGIN_HANDLED;
}

public hns_thetime(id){
    new szDate[32], szTime[32];
    get_time("^3Today: ^4%d.%m.%Y^3", szDate, charsmax(szDate));
    get_time("^3Time: ^4%H:%M:%S^3", szTime, charsmax(szTime));

    client_print_color(id, print_team_blue, "%s %s", gPrefix, szDate);
    client_print_color(id, print_team_blue, "%s %s", gPrefix, szTime);
}

public hns_timeleft(id){
    new iTimeLeft = get_timeleft();
    client_print_color(id, print_team_blue, "%s ^3Timeleft: ^4%d:%02d", gPrefix, iTimeLeft / 60, iTimeLeft % 60);
}

public hns_nextmap(id){
    if(g_bVoteFinished)
        client_print_color(id, print_team_blue, "%s ^3Nextmap is ^4%s", gPrefix, g_szNextMap);
    else
        client_print_color(id, print_team_blue, "%s ^3Nextmap is not selected", gPrefix);
}

public hns_currentmap(id){
    client_print_color(id, print_team_blue, "%s ^3Current map: ^4%s", gPrefix, g_szCurrentMap);
}

NominateMap(id, map[32], map_index){
    new mapInfo[NOMINATEDMAP_INFO];
    new nom_index = is_map_nominated(map_index);
    new size = ArraySize(g_arrNominatedMaps);
    if(nom_index){
        ArrayGetArray(g_arrNominatedMaps, nom_index - 1, mapInfo);
        if(id == mapInfo[n_Player]){
            new iSysTime = get_systime();
            if(g_iLastTimeOfDenominate[id] + MIN_DENOMINATE_TIME <= iSysTime){
                g_iLastTimeOfDenominate[id] = iSysTime;
                g_iNominatedMapsCount[id]--;
                ArrayDeleteItem(g_arrNominatedMaps, nom_index - 1);
                client_print_color(0, print_team_blue, "%s ^3Player ^4%n^3 delete ^4%s^3 from nomination", gPrefix, id, map);
                return 2;
            }
            client_print_color(id, print_team_blue, "%s ^3Stop spamming!", gPrefix);
            return 0;
        }
        client_print_color(id, print_team_blue, "%s ^4%s^3 is already nominated", gPrefix, map);
        return 0;
    }

    if(g_iNominatedMapsCount[id] >= MAX_NOMINATED_MAPS_FOR_PLAYER || size >= MAX_NOMINATED_MAPS){
        client_print_color(id, print_team_blue, "%s ^3You have nominated the max number of maps!", gPrefix);
        return 0;
    }

    mapInfo[n_MapName] = map;
    mapInfo[n_Player] = id;
    mapInfo[n_MapIndex] = map_index;
    ArrayPushArray(g_arrNominatedMaps, mapInfo);

    g_iNominatedMapsCount[id]++;

    client_print_color(0, print_team_blue, "%s ^3Player ^4%n^3 nominated ^4%s^3 to next vote!", gPrefix, id, map);
    return 1;
}

get_map_index(szMapName[]){
    new mapName[32], size = ArraySize(g_arrMaps);
    for(new i; i < size; i++){
        ArrayGetString(g_arrMaps, i, mapName, charsmax(mapName));\
        if(equali(szMapName, mapName))
            return i + 1;
    }

    return 0;
}

find_map_by_subname(map_index, string[32]){
	new mapInfo[32], iSize = ArraySize(g_arrMaps);
	for(new i = map_index; i < iSize; i++){
		ArrayGetString(g_arrMaps, i, mapInfo, charsmax(mapInfo));
		if(containi(mapInfo, string) != -1){
			return i + 1;
		}
	}
	return 0;
}

trim_after_space(text[], index){
    // trim(text);

    if(text[0] != '['){
        return 0;
    }

    new len = strlen(text);

    if(len <= 0 || index >= len){
        return 0
    }

    index++;
    
    for(new i; i < len - index; i++){
        text[i] = text[i + index];
    }

    text[len - index] = 0;
    return 1;
}

is_map_nominated(map_index){
    new mapInfo[NOMINATEDMAP_INFO], size = ArraySize(g_arrNominatedMaps);
    for(new i; i < size; i++){
        ArrayGetArray(g_arrNominatedMaps, i, mapInfo);
        if(map_index == mapInfo[n_MapIndex])
            return i + 1;
    }

    return 0;
}

CheckVotes(){
    g_iVotesNeeded = floatround(get_playersnum() * (PERCENT_OF_VOTED_PLAYERS / 100.0), floatround_ceil);
    if(g_iVotes >= g_iVotesNeeded){
        StartVote();
        return 1;
    } 
    return 0;
}

StartVote(){
    if(g_bVoteStarted || task_exists(TASK_TIMER)) return;

    g_bVoteStarted = true;
    ResetData();

    new Array:arr_finallyMaps = ArrayCreate(32), iCurrentSize = 0; // 32?
    new mMaps[NOMINATEDMAP_INFO], size = ArraySize(g_arrNominatedMaps);
    for(new i = 0; i < MAX_NOMINATED_MAPS && i < size; i++){
        ArrayGetArray(g_arrNominatedMaps, i, mMaps);
        ArrayPushString(arr_finallyMaps, mMaps[n_MapName]);
        iCurrentSize++;
    }

    if(iCurrentSize < ArraySize(g_arrMaps)){
        new randMap[32], globalSize = ArraySize(g_arrMaps);
        for(new i = 0; iCurrentSize < MAX_NOMINATED_MAPS && iCurrentSize < globalSize; i++){ // TODO: оптимизировать
            ArrayGetString(g_arrMaps, random_num(0, globalSize - 1), randMap, charsmax(randMap));
            if(!is_string_in_array(arr_finallyMaps, randMap)){
                ArrayPushString(arr_finallyMaps, randMap);
                iCurrentSize++;
            }
        }
    }

    set_task(1.0, "VoteTime", TASK_TIMER, _, _, "b");
    ArrayPushString(arr_finallyMaps, g_szCurrentMap);
    show_RockTheVoteMenu(arr_finallyMaps, iCurrentSize + 1);
}

public VoteTime(){
    if(g_iVoteTime < VOTE_TIME){
        g_iVoteTime++;
        set_hudmessage(100, 100, 100, -1.0, 0.82, 0, 0.0, 1.01, 0.0, 0.0);
        show_hudmessage(0, "Voting for next map (%i)", VOTE_TIME - g_iVoteTime);
    } else {
        remove_task(TASK_TIMER);
        FinishVote();
    }
}

FinishVote(){
    g_bVoteStarted = false;
    g_bVoteFinished = true;
    g_iVoteTime = 0;

    show_menu(0, 0, "^n", 1)

    new iMax = 0;
    for(new i; i < charsmax(g_matrixMapsOnVote); i++){
        if(g_matrixMapsOnVote[i][v_VotesCount] > g_matrixMapsOnVote[iMax][v_VotesCount])
            iMax = i;
    }
    
    formatex(g_szNextMap, charsmax(g_szNextMap), g_matrixMapsOnVote[iMax][v_MapName]);
    if(equali(g_matrixMapsOnVote[iMax][v_MapName], g_szCurrentMap))
        ExtendMap();
    else {
        set_pcvar_float(g_cvTimelimitPointer, 0.0);
        client_print_color(0, print_team_blue, "%s ^3Next map is ^4%s^3. This is the last round!", gPrefix, g_szNextMap);
    }
}

ExtendMap(){
    g_bVoteFinished = false;
    set_pcvar_float(g_cvTimelimitPointer, get_pcvar_float(g_cvTimelimitPointer) + float(DEFAULT_TIMELIMIT));
    client_print_color(0, print_team_blue, "%s ^4%s^3 will extend for ^4%i^3 minutes", gPrefix, g_szCurrentMap, DEFAULT_TIMELIMIT);
}

ResetData(){
    g_iFinalVotes = 0;
    for(new i; i < sizeof(g_matrixMapsOnVote); i++){
		g_matrixMapsOnVote[i][v_MapName] = "";
		g_matrixMapsOnVote[i][v_VotesCount] = 0;
	}

    new iPlayers[32], iNum; get_players(iPlayers, iNum, "ch");
    for(new id, i; i < iNum; i++){
        id = iPlayers[i];
        g_bIsPlayerVoted[id] = false;
        g_iNominatedMapsCount[id] = 0;
    }

}

stock sum_strings(string1[], string2[]){
    new result[32];
    formatex(result, charsmax(result), "%s%s", string1, string2);
    return result;
}

stock is_string_in_array(Array: array, text[]){
    new size = ArraySize(array);
    if (size == 0)
        return 0;

    new szText[32];
    for(new i; i < size; i++){
        ArrayGetString(array, i, szText, charsmax(szText));
        if(equali(text, szText))
            return 1;
    }

    return 0;
}