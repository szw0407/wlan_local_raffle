# wlan_local_raffle

A cross-platform Flutter application for running local area network (LAN) raffles.

## Background

本项目为本人再移动互联网开发课程的一个实验项目，“ 基于wifidirect或multicast或传感器或二维码等做创意APP设计”，我选择的是 Multicast 方式，实现局域网抽奖。

## Features

- Create or join a raffle room over LAN using UDP multicast.
- Host can add prizes (with quantity), manage participants, and start the raffle.
- Participants can join, confirm participation, and view results in real time.
- Supports multiple platforms: Android, iOS, Windows, macOS, Linux. Web is **not supported** due to the limitations of UDP multicast in web browsers.

## Usage

1. The host creates a room, sets up prizes, and starts the server.
2. Participants join the room by entering the host's port number.
3. After confirming participation, the host can start the raffle.
4. Results are broadcast to all participants.

## Development

- Built with Flutter and Dart.
- Uses UDP multicast for local network communication.
- Prize and user data are managed in-memory during the session.

## Getting Started

1. Install Flutter: https://docs.flutter.dev/get-started/install
2. Run `flutter pub get` to install dependencies.
3. Use `flutter run` to launch the app on your desired platform.
