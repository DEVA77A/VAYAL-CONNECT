# VayalConnect v0.3.2 - Phone/backend connectivity fix

Android debug prerelease for trusted local-network testing.

Cause: the phone and laptop were on different Wi-Fi networks, and the previous APK targeted http://192.168.137.195:8000. The laptop is now at http://10.20.18.111:8000. This freshly built APK compiles that current BACKEND_BASE_URL. The production default remains configurable; no temporary LAN address was hardcoded into Dart source.

Registration timeout and HTTP-client failures now explain that phone and laptop must share Wi-Fi, identify the configured backend URL, and instruct the user to check the running server. No backend contracts or marketplace features changed.

Verified in this run: FastAPI listens on 0.0.0.0:8000; MongoDB is running; /api/docs responds HTTP 200 at the current LAN URL; the LAN login endpoint returns the expected HTTP 401 for synthetic invalid credentials. Existing Private-network Python firewall allow rules match the running interpreter. Full firewall port-filter inspection required administrator access and was denied; no firewall changes were made. No public hosting, port forwarding, or new Public-network firewall rules were configured by this work.

Validation: 8 focused Flutter auth tests passed, including new timeout/client-error cases. Analysis of the changed service and test files found no issues. Debug APK build, ZIP integrity, compiled LAN URL and Brevo key-format scan passed. Previously completed full suites were not rerun; their historical results are documented separately.

Phone verification: the owner confirmed phone-browser API docs access on the earlier 10.196.30.227 Wi-Fi network. During publication the laptop switched to 10.20.18.111; API docs on that latest address are verified from the laptop, but latest-network phone access is awaiting confirmation. No ADB device is connected. Real Farmer/Buyer registration, OTP receipt and login remain NOT TESTED in this run. Prior isolated MongoDB API lifecycle tests used mocked email. No live email was sent; provider acceptance and inbox receipt are not claimed.

Manual testing:
1. Connect phone and laptop to the same trusted Wi-Fi, with no guest-network/client isolation.
2. Keep MongoDB and FastAPI running on the laptop. In PowerShell from C:\VAYAL CONNECT\vayalconnect-backend run .\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 if the server is not already running.
3. Open http://10.20.18.111:8000/api/docs in the phone browser. If it fails, first check Wi-Fi/IP and only then inspect narrowly scoped Private-network firewall access with administrator assistance; never disable the firewall.
4. Download and install vayalconnect-android-test.apk using an authorized GitHub account. The repository stays private.
5. Configure a rotated Brevo transactional credential only in the ignored backend .env. Never use keys exposed in chat. Test Farmer and Buyer registration using controlled inboxes, OTP verification, login, invalid credentials and resend cooldown. Follow docs/MANUAL_TESTING.md.
6. If DHCP changes the laptop IP, use the app's Server IP / URL dialog for the current session or rebuild with the new BACKEND_BASE_URL. No timeout increase was used.

APK size: 166358253 bytes.
APK SHA-256: 7d7a3e5766627228d6cf781dd735daa3cb1cf6f997e9ffe70e3d79acb3ea9390

Publication note: the first upload timed out; the retry encountered DNS failure during a Wi-Fi switch. The existing v0.3.1 release was preserved. The empty v0.3.2 draft is reused for the final current-address APK, which was rebuilt without rerunning the already completed focused tests.
