cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install
cd ..