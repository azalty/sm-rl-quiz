#include <sdktools>
#include <sourcemod>
#include <halflife>
#include <colorvariables>
#undef REQUIRE_PLUGIN
#include <myjbwarden>
#include <store/store-core>
#define REQUIRE_PLUGIN


/*
this plugin needs:
- colorvariables.inc
- MyJailBreak (warden module)
- Sourcemod Store (store-core.inc: updated version - https://forums.alliedmods.net/showthread.php?t=255418)
You will also need this fix: https://github.com/SourceMod-Store/Sourcemod-Store/pull/11

Compiled using SM 1.10
*/

// global variables, so command cannot be run simultaneously
char g_currentThemeID[32];
char g_currentDifficultyID[32];

char question[150];
char answer[150];
char multipleAnswers[15][150];
bool impossible;
int questionCountInt;
bool inQuiz;
bool inPreQuiz;
int currentWarden;
bool isMathQuestion;
bool isWardenQuiz;
int reward;

bool gp_storeCore;

// OnRS 'random/manual questions only' variables
char banned_ids[50][32];
int fail_count;
bool nothing_error;
// -------------------

Handle questionReadTimer;
Handle questionTimer;
Handle questionCountTimer;
Handle questionExpireTimer;
Handle OnRS_InitQuestionsTimer;

Handle gF_OnReward;

ConVar cvarAnswerMode;
ConVar cvarAnswerDelay;
ConVar cvarOnRoundStart_Core;
ConVar cvarOnRoundStart_Delay;
ConVar cvarOnRoundStart_Questions;
ConVar cvarOnRoundStart_Reward;
ConVar cvarMyJailBreak_Core;

KeyValues kv;

/*
Limitations:

- "random order"	'max_amount' limit is 50

- "manual order"	maximum amount of questions is 50
- "manual order"	maximum amount of answers PER question is 15

- Maximum amount of difficulties is 15
-
- Theme/Difficulty names should not exceed 50 characters (or less if using accents éè or different symbols like €)
- Theme/Difficulty IDs should remain short (32 characters or less)
- Questions&answers should not exceed 150 characters. It will never exceed that in normal circumstances.
*/

/*
Because Zephyrus Store doesn't compile in SM 1.10 and that I want this version, I will 'bruteforce' by sending a console command to give Zeph store credits.
*/

public Plugin myinfo = 
{
	name = "RL Quiz System",
	author = "azalty/rlevet",
	description = "A fully configurable advanced quiz system",
	version = "1.0.4",
	url = "github.com/rlevet"
}

public void OnPluginStart()
{
	// Cvars
	cvarAnswerMode = CreateConVar("rl_quiz_answer", "0", "When the answer is found... 0 = ..write the first answer in the list (the first answer should be the best formulated one) | 1 = ..write the answer that the client found", _, true, 0.0, true, 1.0);
	cvarAnswerDelay = CreateConVar("rl_quiz_delay", "30.0", "Delay in seconds people have to answer a question", _, true, 5.0, true, 60.0);
	cvarOnRoundStart_Core = CreateConVar("rl_quiz_onroundstart_core", "0", "0 = Disabled | 1 = Enable this mode. It will send a Quiz at the start of the round", _, true, 0.0, true, 1.0);
	cvarOnRoundStart_Delay = CreateConVar("rl_quiz_onroundstart_delay", "5.0", "Delay in seconds after Round Start to send the Quiz", _, true, 1.0, true, 90.0);
	cvarOnRoundStart_Questions = CreateConVar("rl_quiz_onroundstart_questions", "2", "0 = Only send random math questions ('order random') | 1 = Only send manual questions ('order manuel') | 2 = Send everything", _, true, 0.0, true, 2.0);
	cvarOnRoundStart_Reward = CreateConVar("rl_quiz_onroundstart_reward", "0", "0 = No reward | 1 = Zephyrus store | 2 = SM Store | 3 = Custom (use the forward and include rl_quiz)", _, true, 0.0, true, 3.0);
	cvarMyJailBreak_Core = CreateConVar("rl_quiz_myjailbreak_core", "0", "0 = Disabled | 1 = Enable this mode. It will allow the warden to use the !quiz command to start a Quiz. (REQUIRES MyJailBreak Warden module)", _, true, 0.0, true, 1.0);
	
	// Auto generate config file
	AutoExecConfig();
	
	// Console cmds
	RegConsoleCmd("sm_quiz", DOMenu);
	
	// Events
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);
	
	// Translations
	LoadTranslations("rl.quiz.phrases");
	
	// Init keyvalues
	char kvPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, kvPath, sizeof(kvPath), "configs/rl_quiz.cfg"); //Get cfg file
	kv = new KeyValues("Rl_quiz");
	if (!kv.ImportFromFile(kvPath))
	{
		SetFailState("Unable to import configs/rl_quiz.cfg");
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gF_OnReward = CreateGlobalForward("Rl_quiz_OnReward", ET_Ignore, Param_Cell, Param_Cell);
	
	RegPluginLibrary("rl_quiz");
	
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gp_storeCore = LibraryExists("store/store-core");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "store/store-core"))
	{
		gp_storeCore = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "store/store-core"))
	{
		gp_storeCore = false;
	}
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	inPreQuiz = false;
	inQuiz = false;
	delete questionReadTimer;
	delete questionTimer;
	delete questionCountTimer;
	delete questionExpireTimer;
	delete OnRS_InitQuestionsTimer;
	
	if (cvarOnRoundStart_Core.BoolValue)
	{
		inPreQuiz = true; // blocks any tentative to start a !quiz
		isWardenQuiz = false; // prevents any call and reference to Warden
		
		switch (cvarOnRoundStart_Questions.IntValue)
		{
			case 0:
			{
				// only random math questions
				// false = random math
				fail_count = 0;
				nothing_error = false;
				while (!OnRS_SearchForOrder(false)) // if returns false, no "random" order was found in this theme
				{
					fail_count++;
					if (nothing_error)
					{
						CPrintToChatAll("ERROR: no 'random' order difficulty found in %i themes.", fail_count);
						return;
					}
				}
				OnRS_InitQuestionsTimer = CreateTimer(cvarOnRoundStart_Delay.FloatValue, OnRS_InitQuestions);
			}
			case 1:
			{
				// only manual questions
				// true = manual
				fail_count = 0;
				nothing_error = false;
				while (!OnRS_SearchForOrder(false)) // if returns false, no "random" order was found in this theme
				{
					fail_count++;
					if (nothing_error)
					{
						CPrintToChatAll("ERROR: no 'manual' order difficulty found in %i themes.", fail_count);
						return;
					}
				}
				OnRS_InitQuestionsTimer = CreateTimer(cvarOnRoundStart_Delay.FloatValue, OnRS_InitQuestions);
			}
			default:
			{
				// everything
				
				// Search for a random theme
				kv.Rewind();
				kv.GotoFirstSubKey();
				
				char themelist[50][32]; // up to 50 themes
				int theme_number = -1;
				
				do
				{
					theme_number++;
					// Current key is a section. Browse it recursively.
					
					kv.GetString("id", themelist[theme_number], sizeof(themelist[]));
					//LogMessage("random theme found: %s", themelist[theme_number]);
					
					//kv.GoBack();
				} while (kv.GotoNextKey());
				
				kv.Rewind(); // set up to default for the next check
				
				//int chosen_theme_id = RoundToZero(GetURandomFloat() * (theme_number+0.9999999)); // choose a random theme from 0 to 'theme_number'
				int chosen_theme_id = RoundToZero((GetURandomFloat() * (theme_number+0.9999999)));
				//LogMessage("random float: %f", chosen_theme_id_f);
				//LogMessage("random round: %i", chosen_theme_id);
				//LogMessage("random theme selected: %s (total: %i)", themelist[chosen_theme_id], (theme_number+1));
				g_currentThemeID = themelist[chosen_theme_id]; // set the new theme
				
				
				// Let's find a random difficulty
				kv.GotoFirstSubKey();
				
				char difficultylist[15][32]; // up to 15 difficulties
				int difficulty_number = -1;
				
				// trying to find the Theme..
				do
				{
					// Current key is a section. Browse it recursively.
					
					char theme_id[32];
					kv.GetString("id", theme_id, sizeof(theme_id));
					if (StrEqual(theme_id, g_currentThemeID))
					{
						break; // exit the loop, we are now in the good Theme
					}
					
					//kv.GoBack();
				} while (kv.GotoNextKey());
				
				// Listing all difficulties
				kv.GotoFirstSubKey();
				do
				{
					difficulty_number++;
					
					kv.GetString("id", difficultylist[difficulty_number], sizeof(difficultylist[]));
				} while (kv.GotoNextKey());
				
				int chosen_difficulty_id = RoundToZero((GetURandomFloat() * (difficulty_number+0.9999999)));
				g_currentDifficultyID = difficultylist[chosen_difficulty_id]; // set the new theme
				
				OnRS_InitQuestionsTimer = CreateTimer(cvarOnRoundStart_Delay.FloatValue, OnRS_InitQuestions);
			}
		}
	}
}

public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	inPreQuiz = false;
	inQuiz = false;
	delete questionReadTimer;
	delete questionTimer;
	delete questionCountTimer;
	delete questionExpireTimer;
	delete OnRS_InitQuestionsTimer;
}

public void OnMapEnd()
{
	inPreQuiz = false;
	inQuiz = false;
	delete questionReadTimer;
	delete questionTimer;
	delete questionCountTimer;
	delete questionExpireTimer;
	delete OnRS_InitQuestionsTimer;
}

public void OnClientDisconnect(int client)
{
	if (cvarMyJailBreak_Core.BoolValue)
	{
		if ((inQuiz || inPreQuiz) && (client == currentWarden) && (isWardenQuiz))
		{
			CPrintToChatAll("%T", "MyJB_WardenDisconnected", LANG_SERVER, "Prefix");
			inPreQuiz = false;
			inQuiz = false;
			delete questionReadTimer;
			delete questionTimer;
			delete questionCountTimer;
			delete questionExpireTimer;
		}
	}
}

public void warden_OnWardenRemoved(int client)
{
	if (cvarMyJailBreak_Core.BoolValue)
	{
		if ((inQuiz || inPreQuiz) && (client == currentWarden) && (isWardenQuiz))
		{
			CPrintToChatAll("%T", "MyJB_WardenDisconnected", LANG_SERVER, "Prefix");
			inPreQuiz = false;
			inQuiz = false;
			delete questionReadTimer;
			delete questionTimer;
			delete questionCountTimer;
			delete questionExpireTimer;
		}
	}
}

public Action DOMenu(int client, int args)
{
	if (!cvarMyJailBreak_Core.BoolValue)
	{
		return Plugin_Handled;
	}
	if (!client)
	{
		ReplyToCommand(client, "%T", "Dev_CantFromServerConsole", LANG_SERVER);
		return Plugin_Handled;
	}
	if (client != warden_get())
	{
		CReplyToCommand(client, "%t", "MyJB_MustBeWarden", "Prefix");
		return Plugin_Handled;
	}
	if (inQuiz || inPreQuiz)
	{
		CReplyToCommand(client, "%t", "MyJB_QuizAlreadyInProgress", "Prefix");
		return Plugin_Handled;
	}
	Menu menu = new Menu(DIDMenuHandler);
	menu.SetTitle("Quiz");
	char display[64];
	Format(display, sizeof(display), "%T", "RandomTheme", client);
	menu.AddItem("core_random", "Random theme");
	
	
	// get themes
	kv.Rewind();
	kv.GotoFirstSubKey();
	
	do
	{
		// Current key is a section. Browse it recursively.
		
		char theme_name[50];
		kv.GetSectionName(theme_name, sizeof(theme_name));
		char theme_id[32];
		kv.GetString("id", theme_id, sizeof(theme_id));
		menu.AddItem(theme_id, theme_name);
		
		//kv.GoBack();
	} while (kv.GotoNextKey());
	// --
	
	menu.ExitButton = true;
	menu.Display(client,MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int DIDMenuHandler(Menu menu, MenuAction action, int client, int itemNum) 
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (client != warden_get())
			{
				//LogMessage("[!] Client isn't warden, closing menu");
				delete menu;
				return 0;
			}
			//char info[32];
			
			//GetMenuItem(menu, itemNum, info, sizeof(info));
			GetMenuItem(menu, itemNum, g_currentThemeID, sizeof(g_currentThemeID));
			
			
			// If user selected 'random theme'
			if (StrEqual("core_random", g_currentThemeID))
			{
				kv.Rewind();
				kv.GotoFirstSubKey();
				
				char themelist[50][32]; // up to 50 themes
				int theme_number = -1;
				
				do
				{
					theme_number++;
					// Current key is a section. Browse it recursively.
					
					kv.GetString("id", themelist[theme_number], sizeof(themelist[]));
					//LogMessage("random theme found: %s", themelist[theme_number]);
					
					//kv.GoBack();
				} while (kv.GotoNextKey());
				
				//int chosen_theme_id = RoundToZero(GetURandomFloat() * (theme_number+0.9999999)); // choose a random theme from 0 to 'theme_number'
				float chosen_theme_id_f = (GetURandomFloat() * (theme_number+0.9999999));
				int chosen_theme_id = RoundToZero(chosen_theme_id_f);
				//LogMessage("random float: %f", chosen_theme_id_f);
				//LogMessage("random round: %i", chosen_theme_id);
				//LogMessage("random theme selected: %s (total: %i)", themelist[chosen_theme_id], (theme_number+1));
				g_currentThemeID = themelist[chosen_theme_id]; // set the new theme
			}
			
			
			char theme_name[50];
			
			// get themes
			kv.Rewind();
			kv.GotoFirstSubKey();
			
			// trying to find the Theme..
			do
			{
				// Current key is a section. Browse it recursively.
				
				char theme_id[32];
				kv.GetString("id", theme_id, sizeof(theme_id));
				if (StrEqual(theme_id, g_currentThemeID))
				{
					kv.GetSectionName(theme_name, sizeof(theme_name));
					break; // exit the loop, we are now in the good Theme
				}
				
				//kv.GoBack();
			} while (kv.GotoNextKey());
			
			// -- Lets quickly create the menu so we can add difficulties
			Menu menu2 = new Menu(DIDMenuHandlerHandler);
			menu2.SetTitle(theme_name);
			//LogMessage("menu pre created");
			// --
			
			
			// we are now in the good Theme
			kv.GotoFirstSubKey();
			do
			{
				// Current key is a section. Browse it recursively.
				
				char difficulty_name[50];
				kv.GetSectionName(difficulty_name, sizeof(difficulty_name));
				//LogMessage("parsing %s", difficulty_name);
				char difficulty_id[32];
				kv.GetString("id", difficulty_id, sizeof(difficulty_id));
				menu2.AddItem(difficulty_id, difficulty_name);
				//LogMessage("added %s (%s)", difficulty_id, difficulty_name);
				
				//kv.GoBack();
			} while (kv.GotoNextKey());
			// --
			
			
			menu2.ExitButton = true;
			menu2.ExitBackButton = true;
			if (menu2.Display(client,MENU_TIME_FOREVER))
			{
				//LogMessage("Menu should be displayed");
			}
			else
			{
				//LogMessage("Error! Could not display menu to client!!");
			}
		}
		
		case MenuAction_DisplayItem:
		{
			char info[32];
			menu.GetItem(itemNum, info, sizeof(info));
			
			char display[64];
			if (StrEqual(info, "core_random"))
			{
				Format(display, sizeof(display), "%T", "RandomTheme", client);
				return RedrawMenuItem(display);
			}
		}
		
		case MenuAction_Cancel:
		{
			if(itemNum==MenuCancel_ExitBack)
			{
				if (client != warden_get())
				{
					delete menu;
					return 0;
				}
				DOMenu(client,0);
			}
			//LogMessage("Client %d's menu was cancelled.Reason: %d", client, itemNum); 
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public int DIDMenuHandlerHandler(Menu menu, MenuAction action, int client, int itemNum) 
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int warden = warden_get();
			if (client != warden)
			{
				//LogMessage("[!] Client isn't warden, closing menu");
				delete menu;
				return;
			}
			GetMenuItem(menu, itemNum, g_currentDifficultyID, sizeof(g_currentDifficultyID));
			inPreQuiz = true;
			isWardenQuiz = true;
			currentWarden = warden;
			InitQuestions(client);
		}
		
		case MenuAction_Cancel:
		{
			if(itemNum==MenuCancel_ExitBack)
			{
				if (client != warden_get())
				{
					delete menu;
					return;
				}
				DOMenu(client,0);
			}
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public void InitQuestions(int client)
{
	// empty multipleAnswers string array, fixes issue #3 (github)
	for (int i; i < sizeof(multipleAnswers); i++)
	{
		multipleAnswers[i][0] = '\0';
	}
	
	// get themes
	kv.Rewind();
	kv.GotoFirstSubKey();
	
	char theme_name[50];
	char difficulty_name[50];
	
	// trying to find the Theme..
	do
	{
		// Current key is a section. Browse it recursively.
		
		char theme_id[32];
		kv.GetString("id", theme_id, sizeof(theme_id));
		if (StrEqual(theme_id, g_currentThemeID))
		{
			kv.GetSectionName(theme_name, sizeof(theme_name));
			break; // exit the loop, we are now in the good Theme
		}
		
		//kv.GoBack();
	} while (kv.GotoNextKey());
	
	// trying to find the Difficulty..
	kv.GotoFirstSubKey();
	do
	{
		// Current key is a section. Browse it recursively.
		
		char difficulty_id[32];
		kv.GetString("id", difficulty_id, sizeof(difficulty_id));
		if (StrEqual(difficulty_id, g_currentDifficultyID))
		{
			kv.GetSectionName(difficulty_name, sizeof(difficulty_name));
			break; // exit the loop, we are now in the good Difficulty
		}
		
		//kv.GoBack();
	} while (kv.GotoNextKey());
	
	// We are now in the good difficulty, lets grab "order" and do what we have to after that.
	char param_order[32];
	kv.GetString("order", param_order, sizeof(param_order));
	reward = kv.GetNum("reward", 0);
	
	if (StrEqual(param_order, "random"))
	{
		// random math questions
		int min_individual = kv.GetNum("min_individual");
		int max_individual = kv.GetNum("max_individual");
		
		int min_amount = kv.GetNum("min_amount");
		int max_amount = kv.GetNum("max_amount");
		
		int type_addition = kv.GetNum("type_addition");
		int type_subtraction = kv.GetNum("type_subtraction");
		int type_multiply = kv.GetNum("type_multiply");
		int type_divide = kv.GetNum("type_divide");
		
		// Now lets do a math question
		if (isWardenQuiz)
		{
			char playername[32];
			GetClientName(client, playername, sizeof(playername));
			CPrintToChatAll("%T", "MyJB_WardenDecided", LANG_SERVER, "Prefix", playername, theme_name, difficulty_name);
		}
		else
		{
			CPrintToChatAll("%T", "QuizIncoming", LANG_SERVER, "Prefix", theme_name, difficulty_name);
		}
		if (type_divide)
		{
			CPrintToChatAll("%T", "IfDecimal", LANG_SERVER, "Prefix");
		}
		CPrintToChatAll("%T", "PrepareYourself", LANG_SERVER, "Prefix");
		
		// assign a number to each type
		// type_addition = itself
		int type_total = type_addition + type_subtraction + type_multiply + type_divide; // This is used to know how many types we can get, for the random function.
		
		type_divide = type_addition + type_subtraction + type_multiply + type_divide; // 1 or 2 or 4 or 4
		type_multiply = type_addition + type_subtraction + type_multiply; // 1 or 2 or 3
		type_subtraction = type_addition + type_subtraction; // 1 or 2
		
		
		int random_individual = RoundToZero(GetURandomFloat() * (max_amount-min_amount+0.9999999) + min_amount); // numbers of numbers o_O
		//LogMessage("Number of numbers %i (%i-%i+0.9999999) + %i", random_individual, max_amount, min_amount, min_amount);
		
		
		float random_amount[50]; // max 50 numbers
		int random_type[50]; // max 50 numbers
		float result;
		
		impossible = false;
		
		for (int i = 1; i <= random_individual; i++)
		{
			random_amount[i] = float(RoundToZero(GetURandomFloat() * (max_individual-min_individual+0.9999999) + min_individual)); // amount of each individual number o_O
			random_type[i] = RoundToZero(GetURandomFloat() * (type_total-1+0.9999999) + 1);
			
			if (random_type[i] == type_subtraction)
			{
				if (i == 1)
				{
					Format(question, sizeof(question), "%i", RoundToZero(random_amount[i]));
					result = random_amount[i];
				}
				else
				{
					Format(question, sizeof(question), "%s - %i", question, RoundToZero(random_amount[i]));
					result = result - random_amount[i];
				}
			}
			else if (random_type[i] == type_multiply)
			{
				if (i == 1)
				{
					Format(question, sizeof(question), "%i", RoundToZero(random_amount[i]));
					result = random_amount[i];
				}
				else
				{
					Format(question, sizeof(question), "(%s) * %i", question, RoundToZero(random_amount[i]));
					result = result * random_amount[i];
				}
			}
			else if (random_type[i] == type_divide)
			{
				if (i == 1)
				{
					Format(question, sizeof(question), "%i", RoundToZero(random_amount[i]));
					result = random_amount[i];
				}
				else if (RoundToZero(random_amount[i]) == 0)
				{
					Format(question, sizeof(question), "(%s) / %i", question, RoundToZero(random_amount[i]));
					impossible = true; // in this particular case, it's not possible. Instead of doing +inf, -inf... we will just say it's impossible.
				}
				else
				{
					Format(question, sizeof(question), "(%s) / %i", question, RoundToZero(random_amount[i]));
					result = result / random_amount[i];
				}
			}
			else // if nothing or addition, defaults to addition
			{
				if (i == 1)
				{
					Format(question, sizeof(question), "%i", RoundToZero(random_amount[i]));
					result = random_amount[i];
				}
				else
				{
					Format(question, sizeof(question), "%s + %i", question, RoundToZero(random_amount[i]));
					result = result + random_amount[i];
				}
			}
		}
		
		int finalresult = RoundFloat(result); // nearest integer, easier when dividing
		IntToString(finalresult, answer, sizeof(answer));
		// watch out for impossible = true!
		
		isMathQuestion = true;
		questionReadTimer = CreateTimer(3.0, questionRead, client);
	}
	else
	{
		// manual questions	
		int number_of_questions = 0;
		
		char manual_question[50][150]; // max number of questions 50 - max question size 150
		char manual_answer[50][150];
		
		char keytoget_q[16];
		char keytoget_a[16];
		
		do
		{
			number_of_questions++;
			
			Format(keytoget_q, sizeof(keytoget_q), "question%i", number_of_questions);
			Format(keytoget_a, sizeof(keytoget_a), "answer%i", number_of_questions);
			
			kv.GetString(keytoget_q, manual_question[number_of_questions], sizeof(manual_question[]), "error! key not found");
			kv.GetString(keytoget_a, manual_answer[number_of_questions], sizeof(manual_answer[]), "error! key not found");
		}
		while (!(StrEqual(manual_question[number_of_questions], "error! key not found") || StrEqual(manual_answer[number_of_questions], "error! key not found")))
		
		number_of_questions--;
		
		int random_question = RoundToZero(GetURandomFloat() * (number_of_questions-1+0.9999999) + 1); // choose a random question from 1 to 'number_of_questions'
		
		question = manual_question[random_question];
		//answer = manual_answer[random_question];
		
		ExplodeString(manual_answer[random_question], ";", multipleAnswers, sizeof(multipleAnswers), sizeof(multipleAnswers[]));
		answer = multipleAnswers[0]; // The first answer will always be the one that is showed
		
		if (isWardenQuiz)
		{
			char playername[32];
			GetClientName(client, playername, sizeof(playername));
			CPrintToChatAll("%T", "MyJB_WardenDecided", LANG_SERVER, "Prefix", playername, theme_name, difficulty_name);
		}
		else
		{
			CPrintToChatAll("%T", "QuizIncoming", LANG_SERVER, "Prefix", theme_name, difficulty_name);
		}
		CPrintToChatAll("%T", "PrepareYourself", LANG_SERVER, "Prefix");
		
		isMathQuestion = false;
		impossible = false;
		questionReadTimer = CreateTimer(3.0, questionRead, client);
	}
}

public Action questionRead(Handle timer, int client)
{
	if (isWardenQuiz)
	{
		if (client != warden_get())
		{
			CPrintToChatAll("%T", "MyJB_WardenDisconnected", LANG_SERVER, "Prefix");
			inPreQuiz = false;
			questionReadTimer = null;
			return;
		}
	}
	
	CPrintToChatAll("%T5...", "Prefix", LANG_SERVER);
	questionCountInt = 4;
	questionCountTimer = CreateTimer(1.0, questionCount, client, TIMER_REPEAT);
	questionReadTimer = null;
}

public Action questionCount(Handle timer, int client)
{
	if (isWardenQuiz)
	{
		if (client != warden_get())
		{
			CPrintToChatAll("%T", "MyJB_WardenDisconnected", LANG_SERVER, "Prefix");
			inPreQuiz = false;
			questionCountTimer = null;
			return Plugin_Stop;
		}
	}
	char prefix[64];
	Format(prefix, sizeof(prefix), "%T", "Prefix", LANG_SERVER);
	if (questionCountInt == 0)
	{
		inQuiz = true;
		inPreQuiz = false;
		if (isMathQuestion)
		{
			CPrintToChatAll("%s%s = ?", prefix, question);
		}
		else
		{
			CPrintToChatAll("%s%s", prefix, question);
		}
		
		questionExpireTimer = CreateTimer(cvarAnswerDelay.FloatValue, questionExpire, client);
		questionCountTimer = null;
		return Plugin_Stop;
	}
	
	CPrintToChatAll("%s%i...", prefix, questionCountInt);
	questionCountInt--;
	return Plugin_Continue;
}

public Action questionExpire(Handle timer, int client)
{
	if (inQuiz) // we never know
	{
		if (impossible)
		{
			CPrintToChatAll("%T", "NoOneFoundImpossible", LANG_SERVER, "Prefix");
		}
		else
		{
			CPrintToChatAll("%T", "NoOneFound", LANG_SERVER, "Prefix", answer);
		}
	}
	inQuiz = false;
	questionExpireTimer = null;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args) 
{
	if (!client) // we never know
	{
		return;
	}
	if (!inQuiz)
	{
		//LogMessage("Not in quiz");
		return;
	}
	if ((isWardenQuiz) && (currentWarden != warden_get()))
	{
		CPrintToChatAll("%T", "MyJB_WardenDisconnected", LANG_SERVER, "Prefix");
		inQuiz = false;
		return;
	}

	if (((GetClientTeam(client) == 2) && isWardenQuiz && IsPlayerAlive(client)) || !isWardenQuiz)
	{
		//LogMessage("%N said '%s'", client, args[0]);
		if (impossible)
		{
			char impossible_words[150];
			Format(impossible_words, sizeof(impossible_words), "%T", "ImpossibleWords", LANG_SERVER);
			char impossible_words_list[20][150] // 20 different words, 150 max size
			ExplodeString(impossible_words, ";", impossible_words_list, sizeof(impossible_words_list), sizeof(impossible_words_list[]));
			
			for (int i; i < 20; i++)
			{
				if (StrEqual(args[0], impossible_words_list[i], false))
				{
					if (cvarAnswerMode.BoolValue)
					{
						answer = impossible_words_list[i]; // displays the user's answer if wanted. else, display the first one
					}
					else
					{
						answer = impossible_words_list[0];
					}
					char playername[32];
					GetClientName(client, playername, sizeof(playername));
					CPrintToChatAll("%T", "Found", LANG_SERVER, "Prefix", playername, answer);
					GiveRewards(client);
					inQuiz = false; // no longer in quiz
					delete questionExpireTimer;
					break;
				}
			}
		}
		else if (StrEqual(args[0], answer, false))
		{
			char playername[32];
			GetClientName(client, playername, sizeof(playername));
			CPrintToChatAll("%T", "Found", LANG_SERVER, "Prefix", playername, answer);
			GiveRewards(client);
			inQuiz = false; // no longer in quiz
			delete questionExpireTimer;
		}
		else if (!isMathQuestion)
		{
			for (int i; i < 15; i++)
			{
				if (StrEqual(args[0], multipleAnswers[i], false))
				{
					if (cvarAnswerMode.BoolValue)
					{
						answer = multipleAnswers[i]; // displays the user's answer if wanted. else, display the first one
					}
					char playername[32];
					GetClientName(client, playername, sizeof(playername));
					CPrintToChatAll("%T", "Found", LANG_SERVER, "Prefix", playername, answer);
					GiveRewards(client);
					inQuiz = false; // no longer in quiz
					delete questionExpireTimer;
					break;
				}
			}
		}
	}
}

public void GiveRewards(int client)
{
	if (isWardenQuiz)
	{
		return;
	}
	if (reward == 0)
	{
		return;
	}
	switch (cvarOnRoundStart_Reward.IntValue)
	{
		case 1:
		{
			ServerCommand("sm_givejetons #%i %i", GetClientUserId(client), reward); // as including zeph store breaks everything, here is an alternative
		}
		case 2:
		{
			if (gp_storeCore)
			{
				int accountId = GetSteamAccountID(client);
				Store_GiveCredits(accountId, reward, INVALID_FUNCTION, 0);
			}
			else
			{
				LogMessage("Warning! SM Store is not installed!");
			}
		}
		case 3:
		{
			// well... nothing
		}
		default:
		{
			return;
		}
	}
	Call_StartForward(gF_OnReward);
	Call_PushCell(client);
	Call_PushCell(reward);
	Call_Finish();
	CPrintToChat(client, "%t", "OnRS_YouGot", "Prefix", reward, "CurrencyName");
}

public Action OnRS_InitQuestions(Handle timer)
{
	InitQuestions(0);
	OnRS_InitQuestionsTimer = null;
}

public bool OnRS_SearchForOrder(bool manual_question)
{
	char needed_order[32];
	if (manual_question)
	{
		needed_order = "manual";
	}
	else
	{
		needed_order = "random";
	}
	
	// Search for a random theme
	kv.Rewind();
	kv.GotoFirstSubKey();
	
	char themelist[50][32]; // up to 50 themes
	int theme_number = -1;
	
	do
	{
		theme_number++;
		// Current key is a section. Browse it recursively.
		
		kv.GetString("id", themelist[theme_number], sizeof(themelist[]));
		for (int i; i < fail_count; i++)
		{
			if (StrEqual(themelist[theme_number], banned_ids[i]))
			{
				theme_number--;
				break;
			}
			
		}
		//LogMessage("random theme found: %s", themelist[theme_number]);
		
		//kv.GoBack();
	} while (kv.GotoNextKey());
	
	if (theme_number == -1)
	{
		nothing_error = true;
		return false;
	}
	
	kv.Rewind(); // set up to default for the next check
	
	//int chosen_theme_id = RoundToZero(GetURandomFloat() * (theme_number+0.9999999)); // choose a random theme from 0 to 'theme_number'
	int chosen_theme_id = RoundToZero((GetURandomFloat() * (theme_number+0.9999999)));
	//LogMessage("random float: %f", chosen_theme_id_f);
	//LogMessage("random round: %i", chosen_theme_id);
	//LogMessage("random theme selected: %s (total: %i)", themelist[chosen_theme_id], (theme_number+1));
	g_currentThemeID = themelist[chosen_theme_id]; // set the new theme
	
	
	// Let's find a random difficulty
	kv.GotoFirstSubKey();
	
	char difficultylist[15][32]; // up to 15 difficulties
	int difficulty_number = -1;
	
	// trying to find the Theme..
	do
	{
		// Current key is a section. Browse it recursively.
		
		char theme_id[32];
		kv.GetString("id", theme_id, sizeof(theme_id));
		if (StrEqual(theme_id, g_currentThemeID))
		{
			break; // exit the loop, we are now in the good Theme
		}
		
		//kv.GoBack();
	} while (kv.GotoNextKey());
	
	// Listing all difficulties
	kv.GotoFirstSubKey();
	do
	{
		difficulty_number++;
		
		char param_order[32];
		kv.GetString("order", param_order, sizeof(param_order));
		if (StrEqual(param_order, needed_order))
		{
			kv.GetString("id", difficultylist[difficulty_number], sizeof(difficultylist[]));
		}
		else
		{
			difficulty_number--;
		}
	} while (kv.GotoNextKey());
	
	if (difficulty_number == -1)
	{
		banned_ids[fail_count] = g_currentThemeID;
		return false;
	}
	
	int chosen_difficulty_id = RoundToZero((GetURandomFloat() * (difficulty_number+0.9999999)));
	g_currentDifficultyID = difficultylist[chosen_difficulty_id]; // set the new theme
	
	return true;
}