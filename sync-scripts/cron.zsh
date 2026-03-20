#!/usr/bin/env zsh

cat $SETTINGS_DIR/cronjobs/crontab | perl -pe "s|~|${HOME}|g" | crontab
rm -rf $HOME/scripts
cp -R $SETTINGS_DIR/cronjobs/scripts $HOME
