# IronPulse AI server (runs on your PC)

Phone --USB (adb reverse)--> this server (127.0.0.1:8000) --> Ollama model on your PC.
Nothing is exposed to your Wi-Fi or the internet. Chat history stays on the phone.

## 1. Install Ollama + a model (PowerShell)
    Invoke-WebRequest https://ollama.com/download/OllamaSetup.exe -OutFile "$env:TEMP\OllamaSetup.exe"
    Start-Process "$env:TEMP\OllamaSetup.exe" -Wait
    # open a NEW PowerShell window, then:
    ollama pull llama3.2:3b
    ollama run llama3.2:3b "say hi"      # quick check, then type /bye

llama3.2:3b is about 2 GB and runs on most PCs. With 16 GB+ RAM or a GPU, try qwen2.5:7b or llama3.1:8b
for better answers (change AI_MODEL in .env).

## 2. Install Python (skip if `python --version` already works)
    Invoke-WebRequest https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe -OutFile "$env:TEMP\python.exe"
    Start-Process "$env:TEMP\python.exe" -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1" -Wait
    # open a NEW PowerShell window

## 3. Set up the server (once)
    cd C:\projects\Ironpulse\ai_server
    python -m venv .venv
    .\.venv\Scripts\python.exe -m pip install -r requirements.txt
    Copy-Item .env.example .env
    $token = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 40 | % {[char]$_})
    (Get-Content .env) -replace '^IRONPULSE_AI_TOKEN=.*', "IRONPULSE_AI_TOKEN=$token" | Set-Content .env
    Write-Host "Your token: $token"     # you'll paste this into the app

## 4. Run it (each time)
    cd C:\projects\Ironpulse\ai_server
    .\.venv\Scripts\python.exe app.py
    # in another window, with the phone plugged in:
    adb reverse tcp:8000 tcp:8000

## 5. Connect the app
IronPulse -> AI tab -> settings icon -> Server address `http://127.0.0.1:8000`, paste the token,
tap "Save & test connection". You should see "Connected · llama3.2:3b".

## Using another provider instead of Ollama
Set `AI_PROVIDER=openai_compatible`, `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL` in .env. Your messages (and
the summary you chose to share) then go to that provider under its privacy policy.

## Security notes
- Only binds to 127.0.0.1. Do not change it to 0.0.0.0 without adding HTTPS.
- Token checked in constant time; 10 messages/minute and 200/day limits; 64 KB request limit;
  4,000 characters per message; 90 s model timeout.
- Message content and tokens are never logged.

## Tests
    .\.venv\Scripts\python.exe -m pip install pytest
    .\.venv\Scripts\python.exe -m pytest tests
