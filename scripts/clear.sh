# cd ios
# rm -rf Pods Podfile.lock
# pod cache clean --all
# pod install
# cd ..

adb shell pm clear com.team.visioneer.prayu
cd android
./gradlew clean
cd ..

flutter clean
flutter pub get