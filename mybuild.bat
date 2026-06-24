cd android 
.\gradlew --stop
cd ..
flutter clean
flutter pub get
flutter build apk --release