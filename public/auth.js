/* Phase A1 (consumer auth). Browser-side WebAuthn ceremony driver
 * for /sign-up + /sign-in + /api/auth/recovery.
 *
 * Two ceremonies:
 *   • Registration (sign-up): POST /api/auth/register/options with
 *     username → server emits a PublicKeyCredentialCreationOptions;
 *     navigator.credentials.create(...) prompts the user for
 *     Touch ID / Face ID / hardware key; POST the resulting
 *     PublicKeyCredential to /api/auth/register/verify. On 200
 *     the response carries the user's 10 recovery codes — surface
 *     them ONCE, then unlock the "continue" link.
 *
 *   • Authentication (sign-in): POST /api/auth/login/options with
 *     username → server emits a PublicKeyCredentialRequestOptions
 *     naming the allowed credentials. navigator.credentials.get(...)
 *     prompts. POST result to /api/auth/login/verify. On 200 the
 *     response carries the return_to URL; navigate there.
 *
 * WebAuthn options use raw bytes (ArrayBuffer/Uint8Array) for
 * `challenge`, `user.id`, and credential `id` fields. JSON only
 * supports strings, so the server serializes them as base64url and
 * this script encodes/decodes at the JSON/Web boundary.
 */
(function () {
  'use strict';

  // ---- base64url helpers ---------------------------------------------------
  function b64urlToBuffer(b64url) {
    var b64 = String(b64url).replace(/-/g, '+').replace(/_/g, '/');
    while (b64.length % 4) { b64 += '='; }
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
  }
  function bufferToB64url(buf) {
    var bytes = new Uint8Array(buf);
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  // Walk a CredentialCreationOptions / CredentialRequestOptions tree
  // and convert the well-known buffer fields from base64url strings to
  // ArrayBuffers. Server returns plain JSON; the browser API needs
  // bytes.
  function decodePublicKeyOptions(pk) {
    var out = JSON.parse(JSON.stringify(pk));
    out.challenge = b64urlToBuffer(out.challenge);
    if (out.user && out.user.id) out.user.id = b64urlToBuffer(out.user.id);
    if (Array.isArray(out.excludeCredentials)) {
      out.excludeCredentials = out.excludeCredentials.map(function (c) {
        return Object.assign({}, c, { id: b64urlToBuffer(c.id) });
      });
    }
    if (Array.isArray(out.allowCredentials)) {
      out.allowCredentials = out.allowCredentials.map(function (c) {
        return Object.assign({}, c, { id: b64urlToBuffer(c.id) });
      });
    }
    return out;
  }

  function encodeAttestation(cred) {
    return {
      id:       cred.id,
      rawId:    bufferToB64url(cred.rawId),
      type:     cred.type,
      response: {
        clientDataJSON:    bufferToB64url(cred.response.clientDataJSON),
        attestationObject: bufferToB64url(cred.response.attestationObject),
        transports:        cred.response.getTransports ? cred.response.getTransports() : []
      },
      clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
    };
  }
  function encodeAssertion(cred) {
    return {
      id:       cred.id,
      rawId:    bufferToB64url(cred.rawId),
      type:     cred.type,
      response: {
        clientDataJSON:    bufferToB64url(cred.response.clientDataJSON),
        authenticatorData: bufferToB64url(cred.response.authenticatorData),
        signature:         bufferToB64url(cred.response.signature),
        userHandle:        cred.response.userHandle ? bufferToB64url(cred.response.userHandle) : null
      },
      clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}
    };
  }

  // ---- error display ------------------------------------------------------
  function showError(id, message) {
    var el = document.getElementById(id);
    if (!el) return;
    el.textContent = message || 'Something went wrong. Please try again.';
    el.hidden = false;
  }
  function hideError(id) {
    var el = document.getElementById(id);
    if (el) el.hidden = true;
  }

  // ---- POST JSON helper ---------------------------------------------------
  function postJson(url, body) {
    return fetch(url, {
      method:      'POST',
      credentials: 'same-origin',
      headers:     { 'Content-Type': 'application/json' },
      body:        JSON.stringify(body)
    }).then(function (r) {
      return r.json().then(function (data) { return { ok: r.ok, status: r.status, data: data }; });
    });
  }

  // ---- Sign-up flow -------------------------------------------------------
  function hookSignup() {
    var form = document.getElementById('auth-signup-form');
    if (!form) return;
    var btn = document.getElementById('auth-signup-submit');

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      hideError('auth-signup-error');
      btn.disabled = true;
      btn.textContent = 'Generating passkey…';

      var username    = document.getElementById('auth-username').value.trim().toLowerCase();
      var displayName = document.getElementById('auth-display-name').value.trim();

      postJson('/api/auth/register/options', { username: username, display_name: displayName })
        .then(function (r) {
          if (!r.ok) throw new Error(r.data.error || 'Server rejected the request.');
          return navigator.credentials.create({ publicKey: decodePublicKeyOptions(r.data.publicKey) });
        })
        .then(function (cred) {
          return postJson('/api/auth/register/verify', encodeAttestation(cred));
        })
        .then(function (r) {
          if (!r.ok) throw new Error(r.data.error || 'Could not finish registration.');
          renderRecoveryCodes(r.data.recovery_codes, r.data.username);
        })
        .catch(function (err) {
          showError('auth-signup-error', err.message);
          btn.disabled = false;
          btn.textContent = 'Register passkey';
        });
    });
  }

  function renderRecoveryCodes(codes, username) {
    var card  = document.getElementById('auth-recovery-card');
    var pre   = document.getElementById('auth-recovery-codes');
    var dl    = document.getElementById('auth-recovery-download');
    var cont  = document.getElementById('auth-recovery-continue');
    if (!card || !pre || !dl || !cont) return;

    document.getElementById('auth-signup-form').hidden = true;
    pre.textContent = codes.join('\n');
    card.hidden = false;
    card.scrollIntoView({ behavior: 'smooth', block: 'start' });

    dl.addEventListener('click', function () {
      var blob = new Blob(
        ['Tech Feed Reader — recovery codes for ' + username + '\n' +
         'Generated ' + new Date().toISOString() + '\n' +
         'Each code is single-use. Lose all of these AND your passkeys ' +
         'and you are locked out.\n\n' + codes.join('\n') + '\n'],
        { type: 'text/plain' }
      );
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'tfr-recovery-codes-' + username + '.txt';
      a.click();
      URL.revokeObjectURL(a.href);
      cont.hidden = false;
    });
  }

  // ---- Sign-in flow -------------------------------------------------------
  function hookLogin() {
    var form = document.getElementById('auth-login-form');
    if (!form) return;
    var btn = document.getElementById('auth-login-submit');

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      hideError('auth-login-error');
      btn.disabled = true;
      btn.textContent = 'Waiting for passkey…';

      var username = document.getElementById('auth-username').value.trim().toLowerCase();

      postJson('/api/auth/login/options', { username: username })
        .then(function (r) {
          if (!r.ok) throw new Error(r.data.error || 'Server rejected the request.');
          return navigator.credentials.get({ publicKey: decodePublicKeyOptions(r.data.publicKey) });
        })
        .then(function (cred) {
          return postJson('/api/auth/login/verify', encodeAssertion(cred));
        })
        .then(function (r) {
          if (!r.ok) throw new Error(r.data.error || 'Passkey verification failed.');
          window.location.href = r.data.return_to || '/';
        })
        .catch(function (err) {
          showError('auth-login-error', err.message);
          btn.disabled = false;
          btn.textContent = 'Sign in with passkey';
        });
    });
  }

  // ---- Recovery-code fallback --------------------------------------------
  function hookRecovery() {
    var form = document.getElementById('auth-recovery-form');
    if (!form) return;

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      hideError('auth-recovery-error');
      var code = document.getElementById('auth-recovery-input').value.trim();

      postJson('/api/auth/recovery', { code: code })
        .then(function (r) {
          if (!r.ok) throw new Error(r.data.error || 'Could not sign you in with that code.');
          window.location.href = r.data.return_to || '/';
        })
        .catch(function (err) { showError('auth-recovery-error', err.message); });
    });
  }

  hookSignup();
  hookLogin();
  hookRecovery();
})();
