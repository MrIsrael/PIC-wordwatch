# WordWatch with PIC 16F886
- **This project contains all designs, files and code to build a DIY LED watch, wall mountable, which displays the time with letters.**
Resolution: 5 minutes. The words change each 5 minutes.
You can find an example of how it looks when finished, opening image "Wordwatch finished.jpg".
Entire design was built around PIC 16F886 from Microchip.
Schematic and PCB design made using Autodesk EAGLE 8.0.1.
Assembler code edited and compiled using Microchip MPLAB IDE v8.92.
PICkit 2 was used for .hex transfer to microcontroller.

## Instructions
--> Check the components listed in .sch file.
--> Build the PCB using the PDF prints. There is a great guide to do it yourself, [here] (https://www.youtube.com/watch?v=lvNCKwAcg90).
--> Burn the .hex to PIC 16F886, using a PICkit 2 or compatible PIC programmer.
--> Use the "front layout" images to print a scale screen for the leds. I suggest create a wood screen, etching the letters with laser cutter.
--> Use any AC/DC adaptor to power the clock. Minimum output voltage - current required: 6V DC, 300 mA.

## How to set time
--> Once powered on, press the button to enter set mode. Words will start to blink.
--> Press button again to change and set hours.
--> Wait 10 seconds without pressing the button. Now minutes start to blink.
--> Press button to change and set minutes.
--> Wait another 10 seconds without pressing the button. Program will return to normal mode.

## Maintainer
- [Israel Uribe](https://github.com/MrIsrael)

## License
MIT © [WordWatch](https://github.com/MrIsrael/PIC-wordwatch)
