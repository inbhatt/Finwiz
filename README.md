# Finwiz Trading Dashboard

A Flutter application for tracking stocks, managing positions, and placing orders on the Delta Exchange.

## Overview

This application provides a dashboard for cryptocurrency derivatives trading on the Delta Exchange. It uses the Delta Exchange API for real-time market data, account information, and order management.

## Features

- **Real-time Market Data:** Live stock prices are streamed using WebSockets for instantaneous updates.
- **Position Management:** Users can view their open positions, including quantity, average price, and more.
- **Order Management:** The dashboard displays open orders and provides functionality to:
    - Place new orders (Buy/Sell).
    - Edit existing Take Profit and Stop Loss orders.
    - Set trailing stop losses.
- **Authentication:** The app handles user login and persists session.

## Upcoming Features

### Option Chain Integration

The following features will be added to the dashboard:

1.  **Option Chain Visualization:** A new section will display the option chain for a selected underlying asset.
2.  **Volume Graph:** A chart showing Call and Put volumes at various strike prices (10 above and 10 below the current price).
3.  **Open Interest (OI) Graph:** A chart visualizing the change in Open Interest over time for the same strike prices.

## Technology Stack

- **Frontend:** Flutter
- **Backend/DB:** Firebase Firestore (for storing the list of tracked stocks)
- **API:** Delta Exchange API (REST and WebSocket)
