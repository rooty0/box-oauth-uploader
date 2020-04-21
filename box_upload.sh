#!/usr/bin/env bash
#
# Might be helpfull: https://github.com/box-community/box-curl-samples
: "${BOX_CONFIG:="box_config.json"}"
: "${BOX_SESSION:="box_session.json"}"

if [[ $# -ne 2 ]]
then
  echo "Usage: $0 <file> [file_name_uploaded_box]"
  echo "Examples:"
  echo "  ${0} myfile.img"
  echo "  $(tput bold)SEND_SLACK=1$(tput sgr0) ${0} yourfile.img"
  echo "  ${0} myfile.img box_dest_rename.img"
  echo "To bypass OAuth redefine $(tput bold)\$ACCESS_TOKEN$(tput sgr0). Create your token manually first: https://app.box.com/developers/console"
  echo "  $(tput bold)ACCESS_TOKEN=YOUR_TOKEN$(tput sgr0) SEND_SLACK=1 ${0} aaa.ova"
  exit 1
fi

TARGET_FILE=$1
if [[ -z $2 ]]
then
  BOX_FILENAME=$1
else
  BOX_FILENAME=$2
fi

if [[ ! -f $TARGET_FILE ]]
then
  echo "${TARGET_FILE} not found"
  exit 1
fi

if [[ ! -f $BOX_CONFIG ]]
then
  echo "${BOX_CONFIG} is missing"
  exit 1
fi
: "${CLIENT_ID:="$(jq -r '.CLIENT_ID' $BOX_CONFIG)"}"
: "${CLIENT_SECRET:="$(jq -r '.CLIENT_SECRET' $BOX_CONFIG)"}"
: "${CLIENT_REDIRECT:="$(jq -r '.REDIRECT_URI' $BOX_CONFIG)"}"

check_token() {
  # Returns 0 on success and 1 on false
  curl --request GET "https://api.box.com/2.0/folders/0?fields=id,type,name" \
    --location \
    --head \
    --silent \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" | grep -q "HTTP/1.1 200 OK"
}

get_token() {
  echo "Open your browser and $(tput bold)make sure you're logged in to Box$(tput sgr0). Past the link below to your browser and hit enter:"
  echo "$(tput bold)https://account.box.com/api/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${CLIENT_REDIRECT}$(tput sgr0)"
  echo "Approve request by clicking $(tput bold)[ Grand access to Box ]$(tput sgr0), then you will be redirected to another page"
  echo "Check your browser's query string, it should be something like: ${CLIENT_REDIRECT}?$(tput bold)code=YOUR_CODE$(tput sgr0)"
  echo "Copy paste $(tput bold)YOUR_CODE$(tput sgr0) from query string and hit enter:"
  read -r AUTH_CODE
  if [[ -z $AUTH_CODE ]]
  then
    echo "You didn't specify the CODE"
    return 1
  fi

  curl --location --request POST 'https://api.box.com/oauth2/token' \
        --silent \
        --output "${BOX_SESSION}.new"\
        --data-urlencode 'grant_type=authorization_code' \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "client_secret=${CLIENT_SECRET}" \
        --data-urlencode "code=${AUTH_CODE}" > "${BOX_SESSION}.new"

  if grep -q 'refresh_token' "${BOX_SESSION}.new"
  then
    echo "Success:"
    jq '' "${BOX_SESSION}.new"
    mv "${BOX_SESSION}.new" "${BOX_SESSION}"
    reload_tokens
  else
    echo "Can't get new token. API's answer:"
    jq '' "${BOX_SESSION}.new"
    rm -f "${BOX_SESSION}.new"
    return 1
  fi

}

reload_tokens() {
  ACCESS_TOKEN=$(jq -r '.access_token' $BOX_SESSION)
  REFRESH_TOKEN=$(jq -r '.refresh_token' $BOX_SESSION)
}

if [[ -z $ACCESS_TOKEN ]]
then
  if [[ ! -f $BOX_SESSION ]]
  then
    echo "Let's create a request for token first..."
    get_token || exit 1
  fi
  reload_tokens
fi

echo "Validating sessions token..."

if ! check_token
then
  echo "Trying to get a new token"
  if curl --request POST 'https://api.box.com/oauth2/token' \
          --output "${BOX_SESSION}.renew" \
          --location \
          --silent \
          --header 'Content-Type: application/x-www-form-urlencoded' \
          --data-urlencode 'grant_type=refresh_token' \
          --data-urlencode "client_id=${CLIENT_ID}" \
          --data-urlencode "client_secret=${CLIENT_SECRET}" \
          --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
          --dump-header - | grep -q "HTTP/1.1 200 OK"
  then
    echo "New session token has been successfully installed"
    mv "${BOX_SESSION}.renew" "${BOX_SESSION}"
    reload_tokens
  else
    echo "FAILED:"
    cat "${BOX_SESSION}.renew"
    echo "=> You might want to reauthorize (yes/no):"
    read -r REAUTH
    if [[ $REAUTH != yes ]]
    then
      echo "Ok, exitting, the file ${BOX_SESSION} is not modified"
      exit 1
    else
      if ! get_token
      then
        echo "Unable to get a new token, exitting"
        exit 1
      fi
    fi
  fi
else
  echo "Current token is valid, no need to renew..."
fi

set -e  # If something goes wrong

: "${UPLOAD_FOLDER_ID:="$(jq -r '.UPLOAD_FOLDER_ID' $BOX_CONFIG)"}"


if [[ $TARGET_FILE == $BOX_FILENAME ]]
then
  UPLOAD_MESSAGE_TIP="\"${TARGET_FILE}\""
else
  UPLOAD_MESSAGE_TIP="\"${TARGET_FILE}\" (rename: \"${BOX_FILENAME}\")"
fi
echo "$(tput bold)Uploading your file ${UPLOAD_MESSAGE_TIP} to Box...$(tput sgr0)"
curl --request POST "https://upload.box.com/api/2.0/files/content" \
     --header "Authorization: Bearer ${ACCESS_TOKEN}" \
     --header 'Content-Type: multipart/form-data' \
     --form attributes='{"name":"'"${BOX_FILENAME}"'", "parent":{"id":"'"${UPLOAD_FOLDER_ID}"'"}}' \
     --form file=@"${TARGET_FILE}" > result

: "${SHARED_PUBLIC_LINK:="$(jq -r '.SHARE_PUBLIC_LINK' $BOX_CONFIG)"}"
if [[ $SHARED_PUBLIC_LINK == yes ]]
then
  echo "Creating a sharable link..."
  UPLOADED_FILE_ID=$(jq -r '.entries[0].id' result)
  rm -f result
  curl --request PUT "https://api.box.com/2.0/files/${UPLOADED_FILE_ID}" \
       --silent \
       --header "Authorization: Bearer ${ACCESS_TOKEN}" \
       --data '{ "shared_link": { "access": "open" } }' > dl

  SHARE_LINK_URL=$(jq -r '.shared_link.url' dl)
  rm -f dl
  echo "Your shared public link is: $(tput bold)${SHARE_LINK_URL}$(tput sgr0)"
fi

: "${SEND_SLACK:="$(jq -r '.SEND_SLACK' $BOX_CONFIG)"}"
: "${SLACK_INCOMING_WEBHOOK:="$(jq -r '.SLACK_INCOMING_WEBHOOK' $BOX_CONFIG)"}"
if [[ $SEND_SLACK == yes && $SLACK_INCOMING_WEBHOOK != null ]]
then
  curl --location --request POST "${SLACK_INCOMING_WEBHOOK}" \
        --header 'Content-Type: application/json' \
        --data "{\"text\": \"$(jq -r '.SLACK_MESSAGE' $BOX_CONFIG)\"}"
fi

echo "All done, cya"
