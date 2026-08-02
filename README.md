# WeChat Contact Scanner for macOS

Export information visibly displayed on WeChat for Mac contact-profile pages to a local CSV file. The scanner uses macOS screen capture, on-device OCR, and UI automation. It does not read or modify WeChat's database, send messages, edit contacts, or upload data.

Tested with WeChat for Mac 4.1.2. Other versions or interface layouts may require adjustment.

## Requirements

- macOS with Apple's command-line developer tools (`xcrun swift`)
- WeChat for Mac, logged in
- Terminal permission for Accessibility and Screen & System Audio Recording

If `xcrun swift --version` fails, install the command-line tools first:

```bash
xcode-select --install
```

## Setup and use

1. Clone the repository:

   ```bash
   git clone https://github.com/chiniklaus/wechat-contact-scanner.git
   cd wechat-contact-scanner
   chmod +x run.command
   ```

2. In WeChat, click the green **Contacts** icon in the left sidebar and expand the **Contacts** list.

3. Click the first contact you want to export. Confirm that the right pane displays **Friend Profile** and **WeChat ID**. Do not leave WeChat on a chat-history screen.

4. In Finder, double-click `run.command`. If macOS blocks it, Control-click the file, choose **Open**, and confirm.

5. When prompted, grant Terminal these permissions under **System Settings → Privacy & Security**:

   - **Accessibility**
   - **Screen & System Audio Recording**

   After granting permissions, quit Terminal completely and start `run.command` again.

6. Enter the maximum number of contacts to scan. Start with `1`, then test `5` before attempting a larger batch.

7. Keep the WeChat Contacts window visible and do not use the mouse or keyboard during scanning.

8. When scanning finishes, open `wechat-contacts-YYYYMMDD-HHMMSS.csv` on the Desktop and verify the OCR results.

## Exported fields

- Profile-page first line / remark
- Nickname, when visibly labeled
- WeChat ID
- Phone-like numbers visibly present on the profile
- Region
- Tags, when visible
- Raw OCR text for verification

The scanner cannot retrieve hidden phone numbers or other information that WeChat does not display. OCR can make mistakes, and phone-like strings may require manual verification.

## Privacy and generated files

All recognition runs locally through Apple's Vision framework. During operation, the scanner creates:

- `~/Desktop/wechat-contacts-*.csv`
- `~/Desktop/WeChatContactExporter/last-capture.png`
- `~/Desktop/WeChatContactExporter/last-ocr.txt`

These files may contain personal information. Store them securely and never commit them to Git.

## Stopping and troubleshooting

- Press `Control-C` in Terminal to stop the scanner.
- If it reports that the current screen is not a profile, return to WeChat Contacts and select a profile showing **Friend Profile / WeChat ID**.
- If it cannot move through contacts, first retest with five contacts using WeChat 4.1.2 and the default window layout.
- The requested number is a maximum; duplicate detection may stop the run early if navigation does not advance.

Use this tool only with your own account and handle other people's contact information responsibly.
