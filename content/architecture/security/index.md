---
title: "🛡 Authentication & Identity Management in OpenCHAMI"
description: "OpenCHAMI enforces modern authentication with OIDC, JWT, and machine-based authentication, ensuring secure access to HPC environments."
date: 2025-02-03T00:00:00+00:00
lastmod: 2025-02-03T00:00:00+00:00
draft: false
weight: 20
toc: true
categories: ["Security", "Authentication", "HPC"]
tags: ["OIDC", "JWT", "RBAC", "WireGuard", "TPM"]
contributors: ["Alex Lovell-Troy"]
---

## 📌 Overview
OpenCHAMI enforces a **modern authentication model** designed to replace traditional **SSH keys and password-based authentication** with a **secure, scalable, and identity-driven access system**. This page explains how OpenCHAMI implements **OIDC-based authentication**, **role-based access control (RBAC)**, and **machine identity verification** to ensure secure access.

---

## 1️⃣ Authentication in OpenCHAMI

### **OpenID Connect (OIDC) & JWT-Based Authentication**
Sites generally have their own way of managing sysadmin and user identity.  OpenCHAMI leverages existing authentication through **OpenID Connect (OIDC)** for identity management, allowing seamless integration with existing authentication providers such as:
- 🔐 **LDAP** (Lightweight Directory Access Protocol)  
- 🔐 **Keycloak** (Self-hosted identity provider)  
- 🔐 **Okta, GitHub, or institutional SSO providers**  

When a user or service authenticates with OpenCHAMI:
1. They are redirected to an **OIDC provider** for authentication.  
2. Once authenticated, the provider issues a **JWT (JSON Web Token)**.  
3. OpenCHAMI **validates the JWT** and extracts identity and role information.  
4. The user/service gains **access only to authorized resources** based on their role.  

### **🔧 Why OpenCHAMI Uses OIDC & JWT**
✅ **Stateless Authentication** – No need to store session data; tokens are self-contained.  
✅ **Interoperability** – Works with many enterprise identity providers.  
✅ **Fine-Grained Access Control** – JWT claims can define user roles and permissions.  
✅ **Short-Lived Credentials** – Prevents long-lived access tokens from being exploited.  

---

## 2️⃣ Role-Based Access Control (RBAC)

RBAC ensures that **users, services, and nodes** only have the **minimum necessary privileges** in OpenCHAMI.

### **🔹 Default Roles in OpenCHAMI**
| Role        | Description |
|-------------|------------|
| **Admin**   | Full control over OpenCHAMI services, configurations, and security policies. |
| **Operator** | Can manage clusters, nodes, and jobs but cannot modify security settings. |
| **Scheduler** | Headless accounts with permissions necessary for Job Management |
| **User**    | Can submit and monitor jobs but cannot modify system settings. |
| **Service** | Headless accounts for system components interacting with OpenCHAMI APIs. |

Administrators can **customize roles and permissions** using OIDC group mappings.

### **🔐 How RBAC Works**
1. A user logs in via **OIDC authentication**.  
2. The JWT **includes role claims** (e.g., `"role": "operator"`).  
3. OpenCHAMI **validates** the role and grants **only the necessary access**.  
4. Actions are **restricted** based on the user's role.  

---

## 3️⃣ Machine-Based Authentication

Traditional HPC systems **authenticate users, not machines**—leaving system provisioning vulnerable to **stolen credentials and misconfigurations**.  

OpenCHAMI **flips this model**, requiring **nodes to authenticate themselves before bootstrapping**. This is achieved through:
- **WireGuard-based node identity verification** (covered in the next section).  
- **Future TPM-based machine attestation** to cryptographically verify hardware integrity.  

### **🔹 Why Machine-Based Authentication?**
✅ **No embedded SSH keys** → Eliminates pre-installed secrets in system images.  
✅ **Node-specific identity** → Each node has a unique authentication key.  
✅ **Stronger security guarantees** → Prevents unauthorized machines from joining clusters.  

---

## 4️⃣ Token Management in OpenCHAMI

OpenCHAMI **does not rely on persistent authentication**. Instead, it enforces:
- **Short-lived JWTs** for all users and services.  
- **Refresh tokens** that expire after a predefined period.  
- **Automated token revocation** upon session logout or security policy changes.  

Admins can integrate **multi-factor authentication (MFA)** for an additional layer of security.

---

## 📌 Next Steps
- Learn how OpenCHAMI secures **node authentication** → **[Secure Bootstrapping with WireGuard & Cloud-Init](/blog/2025/02/a-new-approach-to-security-how-openchami-eliminates-hardcoded-ssh-keys/)**.  
- Explore OpenCHAMI’s **API security model**.  
- Join the OpenCHAMI community for **authentication best practices**.  

