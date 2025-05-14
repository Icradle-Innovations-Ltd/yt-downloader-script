@echo off
echo Setting up Git repository...

:: Initialize Git repository
git init

:: Add all files
git add .

:: Commit changes
git commit -m "Initial commit with mobile optimization and error handling improvements"

:: Instructions for pushing to GitHub or other remote repository
echo.
echo Repository initialized and changes committed.
echo.
echo To push to GitHub or another remote repository:
echo 1. Create a new repository on GitHub
echo 2. Run the following commands:
echo    git remote add origin YOUR_REPOSITORY_URL
echo    git push -u origin master
echo.
echo Setup complete!