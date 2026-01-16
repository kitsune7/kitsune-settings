# Setting up Xcode sets up Git
if ! xcode-select -p > /dev/null 2>&1; then
  echo "Xcode is not installed. Installing..."
  xcode-select --install
  sudo xcodebuild -license accept
  echo
fi

git config --global user.name "Christopher Bradshaw"
git config --global user.email "chris.kofox@gmail.com"
