# Troubleshooting

## macOS

**The Accessibility switch is on, but Sightline says it is not allowed.**
macOS ties the permission to the app's signature, and a different build of the app has a different signature. Open **System Settings → Privacy & Security → Accessibility**, select Sightline, remove it with the **−** button, then press **Allow** in Sightline again. From Terminal you can reset it with:

```sh
tccutil reset Accessibility dev.sightline.Sightline
```

**"Sightline can't be opened because Apple cannot check it for malicious software."**
This appears only for manual downloads. Right-click the app, choose **Open**, then **Open** again. The one-line installer avoids this.

**The camera light is on all the time.**
The camera runs while Sightline is active. Pause it from the menu bar or with the shortcut, and the camera turns off.

## Windows

**"Windows blocked the camera, or another app is using it."**
Open **Settings → Privacy & security → Camera** and turn on **Camera access** and **Let desktop apps access your camera**. Close video calls that hold the camera, then choose **Redo Setup…** or restart Sightline.

**SmartScreen says "Windows protected your PC".**
This appears only for manual downloads. Choose **More info**, then **Run anyway**. The one-line installer avoids this.

**A window does not come to the front.**
Windows limits which apps may take focus. Sightline works around this for normal desktop windows. It cannot take focus from apps that run as administrator unless Sightline also runs as administrator.

## Both platforms

**It switches to the wrong screen.**
Redo setup while sitting the way you normally work. During the first part of setup, turn your head toward each dot; do not move only your eyes. Raise **Head turn needed** if it switches too early; lower it if you must turn too far.

**"The camera could not tell these screens apart."**
Your screens are very close together as seen from your seat, so head angles for them overlap. Turn your head clearly toward each screen during setup.

**"You are too far from the camera."**
Sit closer, or choose a camera nearer to you in Preferences.

**Focus jumps while I read another window.**
Raise the pane or window delay, or keep **Wait while I'm typing** on. You can also pause with the shortcut.

Still stuck? [Open an issue](https://github.com/abhayymishraa/sightline/issues/new/choose) with your OS version, camera, and screen layout.
