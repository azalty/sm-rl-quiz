# sm-rl-quiz
A fully configurable advanced quiz system

**[-> Download here <-](https://github.com/rlevet/sm-rl-quiz/releases/latest)**

**[-> Wiki/help here <-](https://github.com/rlevet/sm-rl-quiz/wiki)**

**[-> AlliedModders thread here <-](https://forums.alliedmods.net/showthread.php?t=327552)**

## Features
- Highly configurable (and easy, since everything is explained!)
- Easy integration (for custom rewards)
- Translations (Currently: English, French)
- Quizes are divided by themes, itself divided by difficulties
- Possibility to have multiple good answers for a question
- Can generate random math questions
- Up to 50 themes
  - Up to 15 difficulties per theme
    - Up to 50 questions per difficulty
      - Up to 15 good answers per question

## Available modes:
----------------------------
### On Round Start
This mode will send a quiz at the start of the round. Anyone can answer it.

**Features:**
- Customizable delay (time to wait after round start before sending the quiz)
- Question selection: select if you only want random math questions, manual questions or everything
- Reward: chose if you want to give a reward to the winner with supported currencies (Zeph store & SourceMod Store)
- *Custom currencies are supported if you know how to code, simply use the forward!*
----------------------------
### MyJailBreak Warden
This mode will allow the Warden to start a Quiz with `!quiz`. Only alive Ts will be able to answer it. *I know that a module already exists for this but compatibility is always better!*

**Features:**
- A simple and intuitive menu to start a Quiz
- Warden death and leave detection: the Quiz will stop if something bad happens to the Warden... :-)
----------------------------
## About
This plugin is still in development! Current builds will probably have bugs and aren't finished!
