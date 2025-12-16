# Finwiz Project Overview

This document provides a high-level overview of the Finwiz Flutter project, its architecture, and key functionalities.

## 1. Project Purpose

Finwiz is a trading application designed to interact with the Delta Exchange. It allows users to monitor cryptocurrency markets, manage their trading positions, and analyze derivatives data like option chains.

## 2. Core Technologies

*   **Framework:** Flutter
*   **Database:** Firebase Firestore is used for:
    *   Storing a list of tradable stocks/assets (e.g., in the "STOCKS" collection).
    *   Storing user-specific data, such as orders.
    *   Persisting historical option chain data (Open Interest and Volume) for analysis.
*   **Trading & Data Backend:** [Delta Exchange](https.delta.exchange)
    *   **REST API:** Used for executing actions like placing, updating, and canceling orders.
    *   **WebSocket API:** Used for streaming real-time data, including:
        *   Live asset prices (`v2/ticker`).
        *   User's current positions (`positions`).
        *   Live order updates (`orders`).
*   **Local Storage:** `SharedPreferences` is used to persist user login sessions.

## 3. Application Flow & Key Features

1.  **Initialization (`main.dart`):** The application initializes Firebase and SharedPreferences before launching the UI.
2.  **Login (`login_page.dart`):** The app starts with a login screen. It's assumed that upon successful login, the user's Delta Exchange API Key and Secret are retrieved and set in the `DeltaApi` utility class for subsequent requests.
3.  **Dashboard (`home_page.dart`):** This is the main screen after login. Its responsibilities include:
    *   **Establishing Connection:** It connects to the Delta Exchange WebSocket, authenticates the session, and subscribes to relevant channels.
    *   **Data Fetching:** It fetches an initial list of tradable assets from Firestore.
    *   **Position Management:** Displays a real-time table of the user's open positions. Users can:
        *   View quantity, entry price, etc.
        *   Modify Take Profit and Stop Loss orders associated with a position.
        *   Set or update a Trailing Stop Loss amount.
    *   **Option Chain Analysis:**
        *   When an asset is selected, it fetches detailed option chain data (calls and puts for various strike prices) for a chosen expiry date.
        *   The fetched Open Interest (OI) and Volume data is saved to Firestore for historical tracking.
        *   Presents `VolumeChart` and `OiChart` to visualize the option data.
        *   The data is set to auto-refresh periodically.

## 4. Code Structure

The project follows a standard Flutter structure, separating logic by feature and type.

*   **`lib/`**
    *   **`main.dart`**: The application's entry point.
    *   **`*_page.dart`**: Top-level widgets representing different screens (e.g., `HomePage`, `LoginPage`).
    *   **`utils/`**: Utility and helper classes that abstract core functionalities.
        *   `delta_api.dart`: A crucial class that encapsulates all communication (REST and WebSocket authentication) with the Delta Exchange API. It handles request signing.
        *   `db_utils.dart`: A service class for all Firebase Firestore interactions.
        *   `utils.dart`: General-purpose utilities, including `SharedPreferences` access.
    *   **`widgets/`**: Reusable UI components.
        *   `oi_chart.dart`, `volume_chart.dart`: Custom charts for data visualization.
        *   `edit_order_dialog.dart`: A dialog for modifying order details.
        *   `custom_button.dart`, `custom_text_field.dart`: Themed common widgets.
    *   **`models/`**: (Assumed) Data model classes to structure the application's data.

This overview should serve as a starting point for understanding the project's state and architecture.
