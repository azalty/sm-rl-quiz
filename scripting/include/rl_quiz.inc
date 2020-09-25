/** Double-include prevention */
#if defined _Rl_quiz_included_
  #endinput
#endif
#define _Rl_quiz_included_
 
 
public SharedPlugin __pl_Rl_quiz = 
{
    name = "rl_quiz",
    file = "rl_quiz.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
 
/**
 * Called when a user receives a reward.
 * Use this event to give a reward if you set it to Custom.
 *
 * @param client	The client who got the reward.
 * @param amount	The amount of currency/reward the client got.
 * @NoReturn
 */
forward void Rl_quiz_OnReward(int client, int amount);
