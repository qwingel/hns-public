#include <amxmodx>
#include <fakemeta>

#define PLUGIN "Hide-and-Seek Jumpstats"
#define VERSION "beta"
#define AUTHOR "Antarktida"
#define gPrefix "^3[Jumpstats]"

const TT = 1;
const CT = 2;
const SPEC = 3;
const CLEAR_HUD_TASK = 4444;
const Float:MIN_DISTANCE = 200.0;
const Float:MAX_PERFECT_PRESTRAFE = 300.0;

enum _:PRE_STYLE {
    PRE_OFF,
    PRE_SPEED,
    PRE_FOG
};

enum _:USER_SETTINGS {
    bool:us_bSpeedometer,
    bool:us_bPre,
    us_iPreStyle[PRE_STYLE]
};

new g_lastFog[MAX_PLAYERS], g_iPlayerFog[MAX_PLAYERS];
new g_iLastRed[MAX_PLAYERS], g_iLastGreen[MAX_PLAYERS], g_iLastBlue[MAX_PLAYERS];
new g_playerSettings[MAX_PLAYERS][USER_SETTINGS];
new bool:bOnGround[MAX_PLAYERS];
new bool:g_bHudTaskClear[MAX_PLAYERS];
new Float:g_lastPre[MAX_PLAYERS];
new Float:g_lastOrigin[MAX_PLAYERS][3];


public plugin_precache(){
    register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_init(){
    register_clcmd("say /speed", "hns_speedometer");
    register_clcmd("say /showpre", "hns_showpre");

    register_forward(FM_PlayerPreThink, "fwdPlayerPreThink", 0);
}

public client_putinserver(id){
    LoadSettings(id);
}

public hns_speedometer(id){
    g_playerSettings[id][us_bSpeedometer] = !g_playerSettings[id][us_bSpeedometer];
    client_print_color(id, print_team_red, "%s ^3Speedometer is ^4%s", gPrefix, g_playerSettings[id][us_bSpeedometer] ? "on" : "off")
}

public hns_showpre(id){
    g_playerSettings[id][us_iPreStyle] = g_playerSettings[id][us_iPreStyle] == 2 ? 0 : g_playerSettings[id][us_iPreStyle] + 1; //TODO: peredelat'
    client_print_color(id, print_team_red, "%s ^3Showpre is ^4%s", gPrefix, get_user_prestyle(id));
}

public fwdPlayerPreThink(id){
    if(is_user_alive(id)){
        static flags, button, oldbutton, iGroundFrames[MAX_PLAYERS], Float:flSpeedBefore[32];
        new Float:flSpeed[MAX_PLAYERS], bool:bPerfect[MAX_PLAYERS];
        flags = pev(id, pev_flags);
        button = pev(id, pev_button);
        oldbutton = pev(id, pev_oldbuttons);

        flSpeed[id] = get_user_horizontal_speed(id);
        if(flags & FL_ONGROUND){
            // new Float:Origin[3];
            // pev(id, pev_origin, Origin);
            // if(absf(g_lastOrigin[id][2] - Origin[2]) == 0.0 || button & IN_DUCK && absf(g_lastOrigin[id][2] - Origin[2]) == 18.0){
            //     new Float:fDistance = get_distance_f(g_lastOrigin[id], Origin);
            //     if(fDistance > MIN_DISTANCE){
            //         client_print_color(id, print_team_red, "%s ^4%n's ^3jumped %.2f", gPrefix, id, fDistance);
            //     }
            // }

            // g_lastOrigin[id][0] = Origin[0];
            // g_lastOrigin[id][1] = Origin[1];
            // g_lastOrigin[id][2] = Origin[2];
            bOnGround[id] = true;
            iGroundFrames[id]++;
            g_iPlayerFog[id] = 0;
            if(iGroundFrames[id] <= 5){
                bPerfect[id] = false;
                g_iPlayerFog[id] = iGroundFrames[id];
                if(button & IN_JUMP && ~oldbutton & IN_JUMP && (g_iPlayerFog[id] == 1) == (flSpeedBefore[id] < MAX_PERFECT_PRESTRAFE))
                    bPerfect[id] = true;

                else if(button & IN_DUCK && ~oldbutton & IN_DUCK && g_iPlayerFog[id] == 1)
                    bPerfect[id] = true;
            }

        } else {
            if(bOnGround[id]){
                bOnGround[id] = false;
                g_lastPre[id] = flSpeed[id];
            }

            iGroundFrames[id] = 0;
        }

        flSpeedBefore[id] = flSpeed[id];
        new is_spec[MAX_PLAYERS], szMsg[64];
        for(new i; i < MAX_PLAYERS; i++){
            is_spec[i] = is_user_spectating_player(i, id);
        }

        if(flags & FL_ONGROUND && ((button & IN_JUMP && !(oldbutton & IN_JUMP)) || (button & IN_DUCK && !(oldbutton & IN_DUCK)))){
            for(new i; i < MAX_PLAYERS; i++){
                if(i == id || is_spec[i]){
                    if(g_iPlayerFog[id] == 0 || g_playerSettings[id][us_iPreStyle] != PRE_FOG){
                        g_iLastRed[id] = 140;
                        g_iLastGreen[id] = 140;
                        g_iLastBlue[id] = 140;
                    } else if(bPerfect[id]){
                        g_iLastRed[id] = 0;
                        g_iLastGreen[id] = 255;
                        g_iLastBlue[id] = 0;
                    } else {
                        g_iLastRed[id] = 255;
                        g_iLastGreen[id] = 0;
                        g_iLastBlue[id] = 15;
                    }
                    formatex(szMsg, charsmax(szMsg), "^n[%d FOG]^n%.1f", g_iPlayerFog[id], g_lastPre[id]);
                    g_lastFog[id] = g_iPlayerFog[id];
                    g_bHudTaskClear[id] = false;
                    remove_task(CLEAR_HUD_TASK);
                    new data[1]; data[0] = id;
                    set_task(1.6, "task_ClearPre", CLEAR_HUD_TASK, data, 1);
                }
            }
        }

        new szSpeed[MAX_PLAYERS], szLastInfo[MAX_PLAYERS];

        if(g_playerSettings[id][us_bSpeedometer]){
            formatex(szSpeed, charsmax(szSpeed), "%.0f u/s", flSpeed[id]);
        }

        if(!g_bHudTaskClear[id]){
            if(g_playerSettings[id][us_iPreStyle] == PRE_FOG){
                formatex(szLastInfo, charsmax(szLastInfo), "^n[%d FOG]^n%.1f", g_lastFog[id], g_lastPre[id]);
            } else if(g_playerSettings[id][us_iPreStyle] == PRE_SPEED){
                formatex(szLastInfo, charsmax(szLastInfo), "^n%.1f pre", g_lastPre[id]);
            }
        }

        formatex(szMsg, charsmax(szMsg), "%s%s", szSpeed, szLastInfo);
        set_hudmessage(g_iLastRed[id], g_iLastGreen[id], g_iLastBlue[id], -1.0, 0.62, 0, 0.0, 1.0, 0.1, 0.0, 2);
        for(new i; i < MAX_PLAYERS; i++){
            if(i == id || is_spec[i])
                show_hudmessage(id, szMsg);
        }
    }
}

public task_ClearPre(data[]){
    new id = data[0];
    g_iLastRed[id] = 140;
    g_iLastGreen[id] = 140;
    g_iLastBlue[id] = 140;
    g_bHudTaskClear[id] = true;
}

LoadSettings(id){
    g_playerSettings[id][us_bSpeedometer] = true;
    g_playerSettings[id][us_iPreStyle] = PRE_FOG;
    g_iLastRed[id] = 140;
    g_iLastGreen[id] = 140;
    g_iLastBlue[id] = 140;
    g_bHudTaskClear[id] = true;
}

get_user_prestyle(id){
    new style[16];
    switch(g_playerSettings[id][us_iPreStyle]){
        case 1:{
            style = "prestrafe";
        }

        case 2:{
            style = "fog + prestrafe";
        }

        case 0:{
            style = "off";
        }
    }
    return style;
}

stock is_user_spectating_player(spectator, player){
    if(!is_user_connected(spectator) || !is_user_connected(player))
        return 0;
    
    if(is_user_alive(spectator) || !is_user_alive(player))
        return 0;

    static specmode;
    specmode = pev(spectator, pev_iuser1);

    if(specmode == 3)
        return 0;
        
    if(pev(spectator, pev_iuser2) == player)
        return 1;
        
    return 0;
}

stock Float:absf(Float:a){
    return a < 0 ? (-1) * a : a;
}

stock Float:get_user_horizontal_speed(id){
    new Float:fVelocity[3];
    pev(id, pev_velocity, fVelocity);
    fVelocity[2] = 0.0;
    return vector_length(fVelocity);
}