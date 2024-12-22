# cd ios
# rm -rf Pods Podfile.lock
# pod cache clean --all
# pod install
# cd ..

cd android
./gradlew clean
cd ..

flutter clean
flutter pub get