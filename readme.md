# Box Uploader with OAuth support on pure shell 

This solution automates upload process for Box (box.com) using Standard OAuth 2.0 (User Authentication) 

Should be super helpful for uploading files to Box from command line with almost zero dependencies

It is also can be useful for your CI/CD flow

Features:
- Uploads a file using OAuth 2.0
- Creates a sharable link
- Sends a message with Slack using Slack Webhook

**Please note!** The first run of the script produces a link which you must open in your browser to assign Box permissions.
After this procedure the flow should be fully automated

## How to start

### Create Box App to access Box API

- Login to box
- Go to `Dev Console` --> `My Apps` --> `Create New App` --> `Custom App` --> `Standard OAuth 2.0 (User Authentication)` --> Create your new app
- Make sure you're on `Configuration` tab
- It's highly recommended to set `Redirect URI` to `https://YOURCOMAPY.app.box.com/folder/0`, replace `YOURCOMAPY` with appropriate prefix

### CLI setup

```shell script
git clone https://github.com/rooty0/box-oauth-uploader.git
cd box-oauth-uploader
mv box_config.example.json box_config.json
vim box_config.json  # modify your settings
```
Some option description for `box_config.json`
- You can find your `CLIENT_ID` and `CLIENT_SECRET` on the Box page, `Configuration` tab
- `UPLOAD_FOLDER_ID` The parent folder's **ID** to upload a file to. You can get folder ID by opening the Box folder with your browser and looking to browser's URI. For example you have `https://YOURCOMAPY.app.box.com/folder/81512996001`, so your id will be `81512996001`
- `Redirect URI` option should be the same in the config file and *Box configuration* (see Create Box App to access Box API)
- `SHARED_PUBLIC_LINK` options `yes` or `no`, [see this for more details](https://support.box.com/hc/en-us/articles/360043697094-Creating-Shared-Links)

### Run
Just like that
```shell script
./box_upload aaa.img
```
In case if you want to rename your file on Box run following
```shell script
./box_upload aaa.img bbb.img
```
To overwrite the option(s) run
```shell script
SHARED_PUBLIC_LINK=yes UPLOAD_FOLDER_ID=111222223330 ./box_upload.sh aaa.img
```
You also can change configuration file path (by default it's current working directory)
```shell script
BOX_CONFIG=/tmp/box_config.json ./box_upload.sh aaa.img
```


### Dependencies
- bash
- jq
- curl

## Contribute
Feel free to create a PR

## TODO

- Add *full* support for non-interactive run 

