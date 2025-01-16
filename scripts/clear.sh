flutter clean
flutter pub get

cd ios
rm -rf Pods Podfile.lock
rm -rf ~/Library/Caches/CocoaPods/
rm -rf ~/Library/Developer/Xcode/DerivedData/
pod cache clean --all
pod install
cd ..

cd android
./gradlew clean
cd ..

