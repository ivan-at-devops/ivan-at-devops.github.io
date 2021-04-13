---
title: "Microsoft Teams desktop client in Linux"
tags: Teams install fix apt Linux
---

Current *Microsoft Teams desktop client* has issues in my *Ubuntu 20.04 Focal Fossa*. Let's fix them.

In these pandemic times, you may receive a link to a Microsoft Teams meeting.  
If you want to use the [web client](https://docs.microsoft.com/en-us/microsoftteams/get-clients#web-client), Mozilla Firefox is not supported, Audio/Video do not work.  
Chromium and Chrome work, but you can only see the person that is currently speaking, not all participants. Also, I have to install `snap` to have these browsers, in a system that otherwise does not need it.  

The other option is to use the [desktop client](https://docs.microsoft.com/en-us/microsoftteams/get-clients#linux).  
It installs cleanly, by registering its `apt` repository.  

But here the problem is that it can not get the link url from the browser, and so you can not Join a Meeting as a Guest, outside your Organization.  
It looks like a bug. A little research brings us to a [bug report](https://docs.microsoft.com/en-us/answers/questions/185092/can39t-join-meetings-as-guest-from-linux-teams-app.html).

From that page, we get that version `1.3.00.25560` is the last that works ok, and version `1.3.00.30857` it's the first that has this bug.  
After that, they launched version `1.4.*`, still with this bug, so it seems not prioritary for them.  

## Goal: Use and hold an old package version

Following [this advice](https://askubuntu.com/questions/138284/how-to-downgrade-a-package-via-apt-get), we can run:

``` bash
sudo apt-get update
apt-cache showpkg teams
sudo apt-get install teams=1.3.00.25560
sudo apt-mark hold teams

# aptitude handles dependencies better, but you have to install it

``` 

After that, we see that you have to log in every time you want to use Teams, an annoying process that requires receiving a mail with a code.  
But at least it works, and we learned how to use an older package.


