#!/usr/bin/env bash
# Emoji picker using fuzzel
# Bound to SUPER + PERIOD in Hyprland

set -euo pipefail

# Emoji database - common emojis with descriptions
EMOJI_LIST="😀 grinning face
😃 grinning face with big eyes
😄 grinning face with smiling eyes
😁 beaming face with smiling eyes
😆 grinning squinting face
😅 grinning face with sweat
🤣 rolling on the floor laughing
😂 face with tears of joy
🙂 slightly smiling face
🙃 upside down face
😉 winking face
😊 smiling face with smiling eyes
😇 smiling face with halo
🥰 smiling face with hearts
😍 smiling face with heart eyes
🤩 star struck
😘 face blowing a kiss
😗 kissing face
😚 kissing face with closed eyes
😙 kissing face with smiling eyes
🥲 smiling face with tear
😋 face savoring food
😛 face with tongue
😜 winking face with tongue
🤪 zany face
😝 squinting face with tongue
🤑 money mouth face
🤗 hugging face
🤭 face with hand over mouth
🤫 shushing face
🤔 thinking face
🤐 zipper mouth face
🤨 face with raised eyebrow
😐 neutral face
😑 expressionless face
😶 face without mouth
😏 smirking face
😒 unamused face
🙄 face with rolling eyes
😬 grimacing face
🤥 lying face
😔 pensive face
😪 sleepy face
🤤 drooling face
😴 sleeping face
😷 face with medical mask
🤒 face with thermometer
🤕 face with head bandage
🤢 nauseated face
🤮 face vomiting
🤧 sneezing face
🥵 hot face
🥶 cold face
🥴 woozy face
😵 dizzy face
🤯 exploding head
🤠 cowboy hat face
🥳 partying face
🥸 disguised face
😎 smiling face with sunglasses
🤓 nerd face
🧐 face with monocle
😕 confused face
😟 worried face
🙁 slightly frowning face
😮 face with open mouth
😯 hushed face
😲 astonished face
😳 flushed face
🥺 pleading face
😦 frowning face with open mouth
😧 anguished face
😨 fearful face
😰 anxious face with sweat
😥 sad but relieved face
😢 crying face
😭 loudly crying face
😱 face screaming in fear
😖 confounded face
😣 persevering face
😞 disappointed face
😓 downcast face with sweat
😩 weary face
😫 tired face
🥱 yawning face
😤 face with steam from nose
😡 pouting face
😠 angry face
🤬 face with symbols on mouth
😈 smiling face with horns
👿 angry face with horns
💀 skull
💩 pile of poo
🤡 clown face
👹 ogre
👺 goblin
👻 ghost
👽 alien
👾 alien monster
🤖 robot
😺 grinning cat
😸 grinning cat with smiling eyes
😹 cat with tears of joy
😻 smiling cat with heart eyes
😼 cat with wry smile
😽 kissing cat
🙀 weary cat
😿 crying cat
😾 pouting cat
❤️ red heart
🧡 orange heart
💛 yellow heart
💚 green heart
💙 blue heart
💜 purple heart
🖤 black heart
🤍 white heart
🤎 brown heart
💔 broken heart
❣️ heavy heart exclamation
💕 two hearts
💞 revolving hearts
💓 beating heart
💗 growing heart
💖 sparkling heart
💘 heart with arrow
💝 heart with ribbon
💟 heart decoration
👍 thumbs up
👎 thumbs down
👌 ok hand
✌️ victory hand
🤞 crossed fingers
🤟 love you gesture
🤘 sign of the horns
🤙 call me hand
👈 backhand index pointing left
👉 backhand index pointing right
👆 backhand index pointing up
👇 backhand index pointing down
☝️ index pointing up
✋ raised hand
🤚 raised back of hand
🖐️ hand with fingers splayed
🖖 vulcan salute
👋 waving hand
🤏 pinching hand
✊ raised fist
👊 oncoming fist
🤛 left facing fist
🤜 right facing fist
👏 clapping hands
🙌 raising hands
👐 open hands
🤲 palms up together
🤝 handshake
🙏 folded hands
💪 flexed biceps
🦾 mechanical arm
🦿 mechanical leg
🦵 leg
🦶 foot
👂 ear
🦻 ear with hearing aid
👃 nose
🧠 brain
🫀 anatomical heart
🫁 lungs
🦷 tooth
🦴 bone
👀 eyes
👁️ eye
👅 tongue
👄 mouth
💋 kiss mark
🔥 fire
💫 dizzy
⭐ star
🌟 glowing star
✨ sparkles
⚡ high voltage
💥 collision
💢 anger symbol
💦 sweat droplets
💨 dashing away
🕳️ hole
💣 bomb
💤 zzz
🎉 party popper
🎊 confetti ball
🎈 balloon
🎁 wrapped gift
🏆 trophy
🥇 1st place medal
🥈 2nd place medal
🥉 3rd place medal
🏅 sports medal
🎖️ military medal
🎗️ reminder ribbon
🎫 ticket
🎟️ admission tickets
🎪 circus tent
🎭 performing arts
🎨 artist palette
🎬 clapper board
🎤 microphone
🎧 headphone
🎼 musical score
🎵 musical note
🎶 musical notes
🎹 musical keyboard
🥁 drum
🎷 saxophone
🎺 trumpet
🎸 guitar
🪕 banjo
🎻 violin
🎲 game die
♠️ spade suit
♥️ heart suit
♦️ diamond suit
♣️ club suit
🃏 joker
🀄 mahjong red dragon
🎴 flower playing cards
🎯 direct hit
🎳 bowling
🎮 video game
🕹️ joystick
🎰 slot machine
🧩 puzzle piece
♟️ chess pawn
🎱 pool 8 ball
🪀 yo yo
🪁 kite
🔮 crystal ball
🪄 magic wand
🧿 nazar amulet
🎊 confetti ball
🎉 party popper
🎈 balloon
🎁 wrapped gift
🎀 ribbon
🎗️ reminder ribbon
🎟️ admission tickets
🎫 ticket
🏆 trophy
🏅 sports medal
🥇 1st place medal
🥈 2nd place medal
🥉 3rd place medal
🎖️ military medal
🏵️ rosette
🎗️ reminder ribbon
🎫 ticket
🎟️ admission tickets
🎪 circus tent
🤹 person juggling
🎭 performing arts
🩰 ballet shoes
🎨 artist palette
🎬 clapper board
🎤 microphone
🎧 headphone
🎼 musical score
🎵 musical note
🎶 musical notes
🎹 musical keyboard
🥁 drum
🪘 long drum
🎷 saxophone
🎺 trumpet
🎸 guitar
🪕 banjo
🎻 violin
🪗 accordion
🪈 flute
📱 mobile phone
💻 laptop
🖥️ desktop computer
🖨️ printer
⌨️ keyboard
🖱️ computer mouse
🖲️ trackball
💽 computer disk
💾 floppy disk
💿 optical disk
📀 dvd
🧮 abacus
🎥 movie camera
📹 video camera
📷 camera
📸 camera with flash
📼 videocassette
🔍 magnifying glass tilted left
🔎 magnifying glass tilted right
🕯️ candle
💡 light bulb
🔦 flashlight
🏮 red paper lantern
🪔 diya lamp
📔 notebook with decorative cover
📕 closed book
📖 open book
📗 green book
📘 blue book
📙 orange book
📚 books
📓 notebook
📒 ledger
📃 page with curl
📜 scroll
📄 page facing up
📰 newspaper
🗞️ rolled up newspaper
📑 bookmark tabs
🔖 bookmark
🏷️ label
💰 money bag
🪙 coin
💴 yen banknote
💵 dollar banknote
💶 euro banknote
💷 pound banknote
💸 money with wings
💳 credit card
🧾 receipt
💎 gem stone
⚖️ balance scale
🪜 ladder
🧰 toolbox
🪛 screwdriver
🔧 wrench
🔨 hammer
⛏️ pick
🛠️ hammer and wrench
⚒️ hammer and pick
💣 bomb
🪃 boomerang
🏹 bow and arrow
🛡️ shield
🪚 carpentry saw
🔪 kitchen knife
🗡️ dagger
⚔️ crossed swords
🔫 water pistol
🪄 magic wand
🎣 fishing pole
🤿 diving mask
🎿 skis
🛷 sled
🥌 curling stone
🎯 direct hit
🪀 yo yo
🪁 kite
🎱 pool 8 ball
🔮 crystal ball
🪩 mirror ball
🧿 nazar amulet
🎊 confetti ball
🎉 party popper
🎈 balloon
🎁 wrapped gift
🎀 ribbon
🎗️ reminder ribbon
🎟️ admission tickets
🎫 ticket"

# Create temporary file for emoji list
TEMP_FILE=$(mktemp)
echo "$EMOJI_LIST" > "$TEMP_FILE"

# Use fuzzel to select emoji
SELECTED=$(cat "$TEMP_FILE" | fuzzel --dmenu --prompt="Emoji: " --width=50 --lines=15)

# Clean up temp file
rm "$TEMP_FILE"

# Extract just the emoji (first character)
if [[ -n "$SELECTED" ]]; then
    EMOJI=$(echo "$SELECTED" | cut -d' ' -f1)
    
    # Copy to clipboard using wl-clipboard
    echo -n "$EMOJI" | wl-copy
    
    # Send notification
    notify-send "Emoji Copied" "$EMOJI copied to clipboard" --icon="face-smile" --timeout=2000
    
    # Also type it directly (optional - can be disabled)
    # wtype "$EMOJI"
fi
