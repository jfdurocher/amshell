#!/bin/bash

# amshell.sh version 1.2

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq to use this script."
    exit
fi

# Check if jp2a is installed
if ! command -v jp2a &> /dev/null
then
    echo "jp2a could not be found. Please install jp2a to use this script."
    exit
fi

# Function to get the current playing song and status
get_current_song_and_status() {
    osascript <<EOF
tell application "Music"
    if player state is playing then
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set playStatus to "Playing"
        return trackName & "\t" & trackArtist & "\t" & trackAlbum & "\t" & playStatus
    else if player state is paused then
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set playStatus to "Paused"
        return trackName & "\t" & trackArtist & "\t" & trackAlbum & "\t" & playStatus
    else
        return "\t\t\tStopped"
    end if
end tell
EOF
}

# Function to get the lyrics of the current song from lyrics.ovh
get_current_lyrics() {
    track_name="$1"
    track_artist="$2"
    
    # Replace spaces with %20 for URL encoding
    track_name_formatted=$(echo "$track_name" | sed 's/ /%20/g')
    track_artist_formatted=$(echo "$track_artist" | sed 's/ /%20/g')
    
    # Construct URL for the lyrics API
    url="https://api.lyrics.ovh/v1/$track_artist_formatted/$track_name_formatted"
    
    # Fetch and parse the lyrics with a 3-second timeout
    lyrics=$(curl -s --max-time 3 "$url" | jq -r '.lyrics')
    
    # Check if lyrics were found
    if [ -z "$lyrics" ]; then
        lyrics="No lyrics available"
    fi
    
    echo "$lyrics"
}

# Function to play music
play_music() {
    osascript -e 'tell application "Music" to play'
}

# Function to pause music
pause_music() {
    osascript -e 'tell application "Music" to pause'
}

# Function to skip to the next track
next_track() {
    osascript -e 'tell application "Music" to next track'
}

# Function to go to the previous track
previous_track() {
    osascript -e 'tell application "Music" to previous track'
}

# Function to get the current music artwork and save it to a file
get_artwork() {
    osascript <<EOF
tell application "Music"
    if player state is playing or player state is paused then
        set currentTrack to current track
        set artworkData to data of artwork 1 of currentTrack
        set filePath to POSIX file "/tmp/current_track_artwork.jpg"
        set outFile to open for access filePath with write permission
        write artworkData to outFile
        close access outFile
    end if
end tell
EOF
}

# Function to clear the lyrics from the screen
clear_lyrics_from_screen() {
    for (( i=4; i<36; i++ )); do
        tput cup $i 71
        printf "| %-50s\n" ""
    done
}

# Function to clear song info
clear_song_info_from_screen() {
    for (( i=0; i<4; i++ )); do
        tput cup $i 71
        printf "| %-50s\n" ""
    done
}

# ANSI escape codes for color and formatting
bold_white='\033[1;37m'
blue='\033[34m'
reset='\033[0m'

# Initialize the terminal screen
clear
tput civis  # Hide cursor

# Variables to keep track of the current song, artwork, and lyrics
current_song=""
ascii_art=""
lyrics=""

# Infinite loop to update the song info every second and check for key presses
while true; do
    # Get the current song info and status
    IFS=$'\t' read -r trackName trackArtist trackAlbum playStatus <<< "$(get_current_song_and_status)"
    new_song="$trackName by $trackArtist from the album $trackAlbum"

    # Only update the artwork if the song has changed
    if [[ "$new_song" != "$current_song" ]]; then
        current_song="$new_song"
        get_artwork
        if [ -f /tmp/current_track_artwork.jpg ]; then
            ascii_art=$(jp2a --width=70 --height=36 --color /tmp/current_track_artwork.jpg)
        else
            ascii_art="No artwork available"
        fi
        lyrics=""  # Clear lyrics when the song changes
        clear_song_info_from_screen  # Clear the song info from the screen
        clear_lyrics_from_screen  # Clear the lyrics from the screen
    fi
    
    # Move cursor to top
    tput cup 0 0
    
    # Display the ASCII art and song information side by side
    IFS=$'\n' read -rd '' -a ascii_lines <<<"$ascii_art"
    max_lines=${#ascii_lines[@]}
    max_lines=$(( max_lines > 36 ? 36 : max_lines ))
    for (( i=0; i<$max_lines; i++ )); do
        ascii_line="${ascii_lines[i]}"
        if [[ $i -eq 0 ]]; then
            printf "%-70s | ${bold_white}%s${reset}\n" "$ascii_line" "$trackName"
        elif [[ $i -eq 1 ]]; then
            printf "%-70s | %s\n" "$ascii_line" "$trackArtist"
        elif [[ $i -eq 2 ]]; then
            printf "%-70s | %s\n" "$ascii_line" "$trackAlbum"
        elif [[ $i -eq 3 ]]; then
            printf "%-70s | %s\n" "$ascii_line" "Status: $playStatus"
        else
            printf "%-70s | %s\n" "$ascii_line" ""
        fi
    done

    # Clear the remaining lines where the lyrics will be displayed
    for (( i=max_lines; i<36; i++ )); do
        printf "%-70s | \n" ""
    done

    # Fetch and display the lyrics
    if [[ -z "$lyrics" ]]; then
        lyrics=$(get_current_lyrics "$trackName" "$trackArtist")
    fi
    IFS=$'\n' read -rd '' -a lyrics_lines <<<"$lyrics"
    lyrics_start_line=4
    for (( i=0; i<${#lyrics_lines[@]} && i<$((36-lyrics_start_line)); i++ )); do
        tput cup $((i+lyrics_start_line)) 71
        printf "| ${blue}%s${reset}\n" "${lyrics_lines[i]}"
    done
    
    # Check for user input with a timeout of 3 seconds
    if read -t 3 -n 1 key; then
        case "$key" in
            p) play_music ;;
            a) pause_music ;;
            n) next_track ;;
            b) previous_track ;;
            q)
                tput cnorm  # Show cursor
                clear
                exit 0
                ;;
        esac
    fi

    # Refresh every 3 seconds if no key is pressed
done

tput cnorm  # Show cursor