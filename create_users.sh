#!/bin/bash

# Check if the user file is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <user_file>"
    exit 1
fi

USER_FILE="$1"
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"

# Ensure the log and password files are created
touch "$LOG_FILE"
mkdir -p /var/secure
touch "$PASSWORD_FILE"

# Secure the password file
chmod 600 "$PASSWORD_FILE"

# Function to generate a random password
generate_password() {
    echo "$(openssl rand -base64 12)"
}

# Read the user file line by line
while IFS=';' read -r username groups; do
    # Remove whitespace
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Check if the user already exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists" | tee -a "$LOG_FILE"
        continue
    fi

    # Create personal group for the user if it doesn't exist
    if ! getent group "$username" &>/dev/null; then
        groupadd "$username"
        if [ $? -ne 0 ]; then
            echo "Failed to create group $username" | tee -a "$LOG_FILE"
            continue
        fi
    fi

    # Create user with home directory and personal group
    useradd -m -g "$username" -s /bin/bash "$username"
    if [ $? -ne 0 ]; then
        echo "Failed to create user $username" | tee -a "$LOG_FILE"
        continue
    fi

    # Generate and set password
    password=$(generate_password)
    echo "$username:$password" | chpasswd

    # Store the username and password
    echo "$username,$password" >> "$PASSWORD_FILE"

    # Set ownership and permissions
    chown "$username":"$username" "/home/$username"
    chmod 700 "/home/$username"

    # Add user to additional groups
    IFS=',' read -r -a group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        # Remove whitespace from group name
        group=$(echo "$group" | xargs)

        # Check if group exists, create if not
        if ! getent group "$group" &>/dev/null; then
            groupadd "$group" | tee -a "$LOG_FILE"
        fi

        # Add user to group
        usermod -aG "$group" "$username" | tee -a "$LOG_FILE"
    done

    # Verify if the user was created successfully
    if id "$username" &>/dev/null; then
        echo "User $username successfully created with groups: $groups" | tee -a "$LOG_FILE"
    else
        echo "Failed to create user $username" | tee -a "$LOG_FILE"
    fi

done < "$USER_FILE"
