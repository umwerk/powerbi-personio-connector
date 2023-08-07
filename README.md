# POWER BI - PERSONIO CONNECTOR
## About ##

The project is the work of [Umwerk GmbH](https://umwerk.com/). 

The goal is fetching data from the Personio API and implementing it into Power BI.
The program is written in the Power Query M language.


## Prerequisites

- A Personio account (*Additional info on the Personio API available [here](https://developer.personio.de/docs))*
- [Visual Studio 2017 or 2019](https://visualstudio.microsoft.com/vs/older-downloads/)
- [Power Query SDK](https://marketplace.visualstudio.com/items?itemName=Dakahn.PowerQuerySDK) (*Additional info on the Power Query SDK available [here](https://learn.microsoft.com/en-us/power-query/install-sdk)*)
- [Power BI Desktop](https://powerbi.microsoft.com/en-us/desktop/)

## How to use
- Build the **Personio.mez** file,
- Navigate to **Personio\bin\Debug** and copy the **Personio.mez** file, 
- Copy/Move the .mez file to **Documents\Microsoft Power BI Desktop\Custom Connectors**
#### Note:
    If the directory "Microsoft Power BI Desktop\Custom Connectors" does not exist, create it manually.
    
- In Power BI Desktop, select the **(Not Recommended) Allow any extension to load without validation or warning** option under **File > Options and settings > Options > Security > Data Extensions**.
- Restart Power BI Desktop. Power BI Desktop will automatically load the extensions on restart.
- Choose **Get data** and find  **Personio (beta)** in the list.
- A prompt window will appear where you will be able to define the data time period
- A prompt window will appear, where you will be able to input your credentials *(Username=ClientID" & Password=ClientSecret)*.
