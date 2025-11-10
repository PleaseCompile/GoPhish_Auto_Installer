# 🔧 Troubleshooting Guide - GoPhish Auto Installer

## ❌ ปัญหา: ERR_CONNECTION_RESET (เข้าไม่ได้)

### วินิจฉัยปัญหา:

```bash
# 1. ตรวจสอบ IP ที่ถูกต้อง
curl https://api.ipify.org

# 2. ตรวจสอบว่า GoPhish รันอยู่
sudo systemctl status gophish

# 3. ตรวจสอบ port
sudo ss -tlnp | grep -E '3333|8080'

# 4. ตรวจสอบ UFW
sudo ufw status
```

---

## 🔥 แก้ปัญหา Cloud Provider Firewall

### สำหรับ AWS EC2:

1. ไปที่ **EC2 Console** → **Instances**
2. เลือก instance ของคุณ
3. ไปที่แท็บ **Security** → คลิก **Security Groups**
4. คลิก **Edit inbound rules**
5. เพิ่ม rules:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3333 | 0.0.0.0/0 | GoPhish Admin |
| Custom TCP | TCP | 8080 | 0.0.0.0/0 | GoPhish Phishing |

6. คลิก **Save rules**

### สำหรับ Azure VM:

1. ไปที่ **Virtual Machines** → เลือก VM ของคุณ
2. คลิก **Networking** (ใน Settings)
3. คลิก **Add inbound port rule**
4. เพิ่ม rule สำหรับ port 3333:
   - Source: Any
   - Source port ranges: *
   - Destination: Any
   - Service: Custom
   - Destination port ranges: **3333**
   - Protocol: TCP
   - Action: Allow
   - Priority: 100
   - Name: GoPhish-Admin

5. ทำซ้ำสำหรับ port 8080

### สำหรับ GCP (Google Cloud):

1. ไปที่ **VPC Network** → **Firewall**
2. คลิก **Create Firewall Rule**
3. ตั้งค่า:
   - Name: `allow-gophish`
   - Targets: All instances in the network
   - Source IP ranges: `0.0.0.0/0`
   - Protocols and ports: `tcp:3333,8080`
4. คลิก **Create**

### สำหรับ DigitalOcean:

1. ไปที่ **Networking** → **Firewalls**
2. สร้าง firewall ใหม่หรือแก้ไขที่มีอยู่
3. เพิ่ม **Inbound Rules**:
   - Type: Custom
   - Protocol: TCP
   - Port Range: 3333
   - Sources: All IPv4, All IPv6
   
4. ทำซ้ำสำหรับ port 8080

---

## 🔍 ตรวจสอบ IP ที่ถูกต้อง

ถ้า IP ในเบราว์เซอร์ไม่ตรงกับที่สคริปต์แสดง:

```bash
# ตรวจสอบ Public IP
curl https://api.ipify.org
curl https://ifconfig.co
curl -4 icanhazip.com

# ติดตั้งใหม่ด้วย IP ที่ถูกต้อง
sudo GOPHISH_IP=$(curl -s https://api.ipify.org) bash install_gophish_ip.sh
```

---

## 🧪 ทดสอบการเชื่อมต่อ

### จากเครื่อง Server (ภายใน):

```bash
# ทดสอบ Admin Panel
curl -k https://localhost:3333

# ทดสอบ Phishing Server
curl http://localhost:8080

# ควรได้ response กลับมา (ไม่ใช่ connection refused)
```

### จากเครื่องภายนอก:

```bash
# เปลี่ยน YOUR_IP เป็น IP จริงของ server
telnet YOUR_IP 3333
nc -zv YOUR_IP 3333

# ถ้า connection refused = firewall บล็อก
# ถ้า connection timeout = Security Group บล็อก
```

---

## 🔐 ตรวจสอบ SSL Certificate

ถ้าเข้าได้แต่มีปัญหา SSL:

```bash
# ดู certificate
openssl s_client -connect YOUR_IP:3333 -showcerts

# สร้าง certificate ใหม่
sudo rm -rf /etc/ssl/gophish/*
sudo systemctl restart gophish
```

---

## 📝 ดูรหัสผ่าน Admin

```bash
# ดูรหัสผ่านจาก logs
sudo journalctl -u gophish | grep 'Please login with'

# หรือดู logs ล่าสุด
sudo journalctl -u gophish -n 100
```

---

## 🔄 Reinstall (ถ้าทุกอย่างล้มเหลว)

```bash
# ลบการติดตั้งเดิม
sudo systemctl stop gophish
sudo systemctl disable gophish
sudo rm /etc/systemd/system/gophish.service
sudo rm -rf /opt/gophish
sudo rm -rf /etc/ssl/gophish
sudo systemctl daemon-reload

# ติดตั้งใหม่
curl -fsSL https://raw.githubusercontent.com/PleaseCompile/GoPhish_Auto_Installer/main/install_gophish_ip.sh | sudo bash
```

---

## 📊 Checklist การแก้ปัญหา

- [ ] GoPhish service รันอยู่ (`sudo systemctl status gophish`)
- [ ] Port 3333 และ 8080 เปิดอยู่ (`sudo ss -tlnp | grep -E '3333|8080'`)
- [ ] UFW firewall เปิด port แล้ว (`sudo ufw status`)
- [ ] **Cloud Security Group/NSG เปิด port แล้ว** ⬅️ **สำคัญที่สุด!**
- [ ] IP ที่ใช้ถูกต้อง
- [ ] ทดสอบจากภายในเครื่องได้ (`curl -k https://localhost:3333`)
- [ ] ทดสอบจากภายนอกได้ (`telnet IP 3333`)

---

## 💡 Tips

### ตั้งค่าความปลอดภัยที่ดีกว่า:

แทนที่จะเปิด `0.0.0.0/0` ให้เปิดเฉพาะ IP ที่ต้องการ:

**AWS Security Group:**
```
Source: YOUR_OFFICE_IP/32
```

**UFW:**
```bash
sudo ufw delete allow 3333/tcp
sudo ufw allow from YOUR_OFFICE_IP to any port 3333 proto tcp
sudo ufw reload
```

---

## 📞 ยังไม่ได้?

ให้ข้อมูลนี้เพื่อขอความช่วยเหลือ:

```bash
# รวบรวมข้อมูล debug
echo "=== System Info ==="
uname -a
cat /etc/os-release

echo "=== Service Status ==="
sudo systemctl status gophish

echo "=== Port Status ==="
sudo ss -tlnp | grep -E '3333|8080'

echo "=== Firewall Status ==="
sudo ufw status verbose

echo "=== Public IP ==="
curl -s https://api.ipify.org

echo "=== Logs ==="
sudo journalctl -u gophish -n 50
```

แล้วแชร์ output มา!
