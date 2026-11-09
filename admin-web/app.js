import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const client = createClient(
  window.PASYALPH_SUPABASE_URL,
  window.PASYALPH_SUPABASE_PUBLISHABLE_KEY,
);
const byId = (id) => document.getElementById(id);
const authPanel = byId('auth-panel');
const workspace = byId('workspace');
const authMessage = byId('auth-message');
const workspaceMessage = byId('workspace-message');
const placeForm = byId('place-form');
const promotionForm = byId('promotion-form');
const adminForm = byId('admin-form');
let places = [];
let promotions = [];
let applications = [];
let reports = [];
let editingPlace = null;
let editingPromotion = null;
let recoveryMode = false;

function notice(element, message = '', isError = false) {
  element.textContent = message;
  element.classList.toggle('error', isError);
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

function setBusy(form, busy) {
  for (const control of form.querySelectorAll('button, input, select, textarea')) {
    control.disabled = busy;
  }
}

function setRecoveryVisible(visible) {
  recoveryMode = visible;
  byId('login-form').hidden = visible;
  byId('forgot-link').hidden = visible;
  byId('recovery-form').hidden = !visible;
}

function localDateTime(value) {
  const date = new Date(value);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function timestamp(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) throw new Error('Enter valid promotion dates.');
  return parsed.toISOString();
}

async function showSession(session) {
  if (!session) {
    authPanel.hidden = false;
    workspace.hidden = true;
    byId('account-bar').hidden = true;
    return;
  }

  const { data: profile, error } = await client
    .from('profiles')
    .select('role')
    .eq('id', session.user.id)
    .maybeSingle();
  if (error) {
    notice(authMessage, error.message, true);
    return;
  }
  if (profile?.role !== 'admin') {
    notice(authMessage, 'Administrator access is required for this website.', true);
    await client.auth.signOut();
    return;
  }

  authPanel.hidden = true;
  workspace.hidden = false;
  byId('account-bar').hidden = false;
  byId('account-email').textContent = session.user.email ?? '';
  await loadData();
}

function renderPlaces() {
  byId('place-count').textContent = places.length;
  const container = byId('places-list');
  if (places.length === 0) {
    container.innerHTML = '<p class="empty">No places yet. Add your first place using the form.</p>';
    return;
  }
  container.innerHTML = places.map((place) => `
    <article class="record">
      <div>
        <h3>${escapeHtml(place.name)}</h3>
        <p>${escapeHtml(place.category)} · ${escapeHtml(place.address)}</p>
        <span class="badge">${escapeHtml(place.status)}${place.sponsored ? ' · Sponsored' : ''}</span>
      </div>
      <div class="record-actions">
        <button type="button" data-edit-place="${escapeHtml(place.id)}">Edit</button>
        <button class="delete" type="button" data-delete-place="${escapeHtml(place.id)}">Delete</button>
      </div>
    </article>`).join('');

  container.querySelectorAll('[data-edit-place]').forEach((button) => {
    button.addEventListener('click', () => editPlace(button.dataset.editPlace));
  });
  container.querySelectorAll('[data-delete-place]').forEach((button) => {
    button.addEventListener('click', () => deletePlace(button.dataset.deletePlace));
  });
}

function renderPromotions() {
  byId('promotion-count').textContent = promotions.length;
  const container = byId('promotions-list');
  if (promotions.length === 0) {
    container.innerHTML = '<p class="empty">No promotions yet. Add a campaign using the form.</p>';
    return;
  }
  container.innerHTML = promotions.map((promotion) => {
    const place = places.find((item) => item.id === promotion.place_id);
    return `
      <article class="record">
        <div>
          <h3>${escapeHtml(promotion.title)}</h3>
          <p>${escapeHtml(place?.name ?? 'Place unavailable')}${promotion.discount_label ? ` · ${escapeHtml(promotion.discount_label)}` : ''}</p>
          <p>${escapeHtml(new Date(promotion.starts_at).toLocaleString())} – ${escapeHtml(new Date(promotion.ends_at).toLocaleString())}</p>
          <span class="badge">${promotion.active ? 'Active' : 'Paused'}</span>
        </div>
        <div class="record-actions">
          <button type="button" data-edit-promotion="${escapeHtml(promotion.id)}">Edit</button>
          <button class="delete" type="button" data-delete-promotion="${escapeHtml(promotion.id)}">Delete</button>
        </div>
      </article>`;
  }).join('');

  container.querySelectorAll('[data-edit-promotion]').forEach((button) => {
    button.addEventListener('click', () => editPromotion(button.dataset.editPromotion));
  });
  container.querySelectorAll('[data-delete-promotion]').forEach((button) => {
    button.addEventListener('click', () => deletePromotion(button.dataset.deletePromotion));
  });
}

function renderApplications() {
  const pending = applications.filter((application) => application.status === 'Pending review');
  byId('application-count').textContent = pending.length;
  const container = byId('applications-list');
  if (pending.length === 0) {
    container.innerHTML = '<p class="empty">There are no business applications awaiting review.</p>';
    return;
  }
  container.innerHTML = pending.map((application) => `
    <article class="record">
      <div>
        <h3>${escapeHtml(application.business_name)}</h3>
        <p>${escapeHtml(application.legal_name)} · ${escapeHtml(application.address)}</p>
        <p>${escapeHtml(application.phone)} · Permit: ${escapeHtml(application.permit_reference)}</p>
        <p>${escapeHtml(application.description)}</p>
      </div>
      <div class="record-actions">
        <button type="button" data-approve-application="${escapeHtml(application.id)}">Approve</button>
        <button class="delete" type="button" data-reject-application="${escapeHtml(application.id)}">Reject</button>
      </div>
    </article>`).join('');
  container.querySelectorAll('[data-approve-application]').forEach((button) => {
    button.addEventListener('click', () => moderateApplication(button.dataset.approveApplication, true));
  });
  container.querySelectorAll('[data-reject-application]').forEach((button) => {
    button.addEventListener('click', () => moderateApplication(button.dataset.rejectApplication, false));
  });
}

function renderReports() {
  byId('report-count').textContent = reports.filter((report) => report.status === 'Open').length;
  const container = byId('reports-list');
  if (reports.length === 0) {
    container.innerHTML = '<p class="empty">There are no place reports.</p>';
    return;
  }
  container.innerHTML = reports.map((report) => {
    const place = places.find((item) => item.id === report.place_id);
    return `
      <article class="record">
        <div>
          <h3>${escapeHtml(place?.name ?? report.place_id)}</h3>
          <p>${escapeHtml(report.reason)}</p>
          <span class="badge">${escapeHtml(report.status)}</span>
        </div>
        ${report.status === 'Open' ? `<div class="record-actions"><button type="button" data-resolve-report="${escapeHtml(report.id)}">Mark resolved</button></div>` : ''}
      </article>`;
  }).join('');
  container.querySelectorAll('[data-resolve-report]').forEach((button) => {
    button.addEventListener('click', () => resolveReport(button.dataset.resolveReport));
  });
}

function renderPlaceOptions(selectedId = '') {
  const select = promotionForm.elements.place_id;
  select.innerHTML = '<option value="">Select a place</option>' + places.map((place) =>
    `<option value="${escapeHtml(place.id)}">${escapeHtml(place.name)}</option>`).join('');
  select.value = selectedId;
}

async function loadData() {
  notice(workspaceMessage, 'Loading database records…');
  try {
    const [placeResult, promotionResult, applicationResult, reportResult] = await Promise.all([
      client.from('places').select('*').order('name'),
      client.from('promotions').select('*').order('starts_at', { ascending: false }),
      client.from('business_applications').select('*').order('created_at', { ascending: false }),
      client.from('reports').select('*').order('created_at', { ascending: false }),
    ]);
    if (placeResult.error) throw placeResult.error;
    if (promotionResult.error) throw promotionResult.error;
    if (applicationResult.error) throw applicationResult.error;
    if (reportResult.error) throw reportResult.error;
    places = placeResult.data ?? [];
    promotions = promotionResult.data ?? [];
    applications = applicationResult.data ?? [];
    reports = reportResult.data ?? [];
    renderPlaces();
    renderPlaceOptions();
    renderPromotions();
    renderApplications();
    renderReports();
    notice(workspaceMessage);
  } catch (error) {
    notice(workspaceMessage, `Could not load data: ${error.message}`, true);
  }
}

function resetPlaceForm() {
  editingPlace = null;
  placeForm.reset();
  placeForm.elements.status.value = 'Verified';
  byId('place-form-title').textContent = 'Add a place';
  byId('place-cancel').hidden = true;
}

function editPlace(id) {
  const place = places.find((item) => item.id === id);
  if (!place) return;
  editingPlace = place.id;
  for (const key of ['name', 'category', 'status', 'address', 'description', 'image', 'lat', 'lng', 'hours', 'contact', 'rates']) {
    placeForm.elements[key].value = place[key] ?? '';
  }
  for (const key of ['amenities', 'routes']) {
    placeForm.elements[key].value = Array.isArray(place[key]) ? place[key].join(', ') : '';
  }
  placeForm.elements.sponsored.checked = place.sponsored === true;
  byId('place-form-title').textContent = 'Edit place';
  byId('place-cancel').hidden = false;
  placeForm.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function deletePlace(id) {
  const place = places.find((item) => item.id === id);
  if (!place || !window.confirm(`Permanently delete "${place.name}" and its linked promotions?`)) return;
  const { error } = await client.from('places').delete().eq('id', id);
  if (error) {
    notice(workspaceMessage, `Could not delete place: ${error.message}`, true);
    return;
  }
  await loadData();
}

placeForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  setBusy(placeForm, true);
  notice(workspaceMessage);
  const form = new FormData(placeForm);
  const lat = Number(form.get('lat'));
  const lng = Number(form.get('lng'));
  const enteredImage = String(form.get('image') ?? '').trim();
  const image = enteredImage.startsWith('assets/')
    ? `/${enteredImage}`
    : enteredImage;
  const isLocalImage = image.startsWith('/') && !image.startsWith('//');
  if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
    notice(workspaceMessage, 'Enter valid latitude and longitude coordinates.', true);
    setBusy(placeForm, false);
    return;
  }
  if (image && !isLocalImage && !/^https:\/\//i.test(image)) {
    notice(workspaceMessage, 'Use an HTTPS image URL or a path beginning with /.', true);
    setBusy(placeForm, false);
    return;
  }
  const payload = {
    name: String(form.get('name')).trim(),
    category: form.get('category'),
    status: form.get('status'),
    address: String(form.get('address')).trim(),
    description: String(form.get('description')).trim(),
    image: image || '/assets/images/pasyalph-new-logo.jpg',
    lat,
    lng,
    hours: String(form.get('hours') ?? '').trim(),
    contact: String(form.get('contact') ?? '').trim(),
    rates: String(form.get('rates') ?? '').trim(),
    amenities: String(form.get('amenities') ?? '').split(',').map((item) => item.trim()).filter(Boolean).slice(0, 20),
    routes: String(form.get('routes') ?? '').split(',').map((item) => item.trim()).filter(Boolean).slice(0, 20),
    sponsored: form.get('sponsored') === 'on',
    ...(!editingPlace ? { owner_id: null } : {}),
  };
  const result = editingPlace
    ? await client.from('places').update(payload).eq('id', editingPlace)
    : await client.from('places').insert(payload);
  setBusy(placeForm, false);
  if (result.error) {
    notice(workspaceMessage, `Could not save place: ${result.error.message}`, true);
    return;
  }
  resetPlaceForm();
  await loadData();
  notice(workspaceMessage, 'Place saved.');
});

function resetPromotionForm() {
  editingPromotion = null;
  promotionForm.reset();
  promotionForm.elements.active.checked = true;
  renderPlaceOptions();
  byId('promotion-form-title').textContent = 'Add a promotion';
  byId('promotion-cancel').hidden = true;
}

function editPromotion(id) {
  const promotion = promotions.find((item) => item.id === id);
  if (!promotion) return;
  editingPromotion = promotion.id;
  renderPlaceOptions(promotion.place_id);
  for (const key of ['title', 'discount_label', 'description']) {
    promotionForm.elements[key].value = promotion[key] ?? '';
  }
  promotionForm.elements.starts_at.value = localDateTime(promotion.starts_at);
  promotionForm.elements.ends_at.value = localDateTime(promotion.ends_at);
  promotionForm.elements.active.checked = promotion.active === true;
  byId('promotion-form-title').textContent = 'Edit promotion';
  byId('promotion-cancel').hidden = false;
  promotionForm.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function deletePromotion(id) {
  const promotion = promotions.find((item) => item.id === id);
  if (!promotion || !window.confirm(`Permanently delete "${promotion.title}"?`)) return;
  const { error } = await client.from('promotions').delete().eq('id', id);
  if (error) {
    notice(workspaceMessage, `Could not delete promotion: ${error.message}`, true);
    return;
  }
  await loadData();
}

async function moderateApplication(id, approved) {
  const action = approved ? 'approve' : 'reject';
  if (!window.confirm(`Are you sure you want to ${action} this business application?`)) return;
  const { error } = await client.rpc('moderate_application', {
    application_id: id,
    approved,
  });
  if (error) {
    notice(workspaceMessage, `Could not ${action} application: ${error.message}`, true);
    return;
  }
  await loadData();
}

async function resolveReport(id) {
  const { error } = await client.from('reports').update({ status: 'Resolved' }).eq('id', id);
  if (error) {
    notice(workspaceMessage, `Could not resolve report: ${error.message}`, true);
    return;
  }
  await loadData();
}

adminForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = new FormData(adminForm);
  const password = String(form.get('password'));
  if (password !== form.get('confirmation')) {
    notice(workspaceMessage, 'The passwords do not match.', true);
    return;
  }
  if (form.get('confirm-understanding') !== 'on') {
    notice(workspaceMessage, 'Confirm that you will share the password securely.', true);
    return;
  }

  setBusy(adminForm, true);
  notice(workspaceMessage);
  const { data, error } = await client.functions.invoke('admin-create-user', {
    body: {
      email: String(form.get('email')).trim(),
      password,
    },
  });
  setBusy(adminForm, false);
  if (error) {
    let message = error.message;
    if (error.context && typeof error.context.json === 'function') {
      const details = await error.context.json().catch(() => null);
      if (details?.error) message = details.error;
    }
    notice(workspaceMessage, `Could not create admin: ${message}`, true);
    return;
  }

  adminForm.reset();
  notice(workspaceMessage, `Administrator account created for ${data.email}. Share the temporary password securely.`);
});

promotionForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  setBusy(promotionForm, true);
  notice(workspaceMessage);
  try {
    const form = new FormData(promotionForm);
    const payload = {
      place_id: form.get('place_id'),
      title: String(form.get('title')).trim(),
      description: String(form.get('description') ?? '').trim(),
      discount_label: String(form.get('discount_label') ?? '').trim(),
      starts_at: timestamp(form.get('starts_at')),
      ends_at: timestamp(form.get('ends_at')),
      active: form.get('active') === 'on',
    };
    if (new Date(payload.ends_at) <= new Date(payload.starts_at)) {
      throw new Error('The end date must be after the start date.');
    }
    const result = editingPromotion
      ? await client.from('promotions').update(payload).eq('id', editingPromotion)
      : await client.from('promotions').insert(payload);
    if (result.error) throw result.error;
    resetPromotionForm();
    await loadData();
    notice(workspaceMessage, 'Promotion saved.');
  } catch (error) {
    notice(workspaceMessage, `Could not save promotion: ${error.message}`, true);
  } finally {
    setBusy(promotionForm, false);
  }
});

byId('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  setBusy(event.currentTarget, true);
  notice(authMessage);
  const form = new FormData(event.currentTarget);
  const { data, error } = await client.auth.signInWithPassword({
    email: String(form.get('email')).trim(),
    password: form.get('password'),
  });
  setBusy(event.currentTarget, false);
  if (error) {
    notice(authMessage, error.message, true);
    return;
  }
  await showSession(data.session);
});

byId('forgot-link').addEventListener('click', async () => {
  const email = String(byId('login-form').elements.email.value).trim();
  if (!email) {
    notice(authMessage, 'Enter your email address first.', true);
    return;
  }
  const redirectTo = new URL(window.location.pathname, window.location.origin).toString();
  const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo });
  notice(authMessage, error
    ? `Could not send the reset email: ${error.message}`
    : 'If the account exists, a secure password reset link will arrive in your inbox.', Boolean(error));
});

byId('recovery-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  const password = String(form.get('password'));
  if (password !== form.get('confirmation')) {
    notice(authMessage, 'The passwords do not match.', true);
    return;
  }
  setBusy(event.currentTarget, true);
  const { error } = await client.auth.updateUser({ password });
  setBusy(event.currentTarget, false);
  if (error) {
    notice(authMessage, `Could not update password: ${error.message}`, true);
    return;
  }
  setRecoveryVisible(false);
  notice(authMessage, 'Password updated. Sign in with your new password.');
  await client.auth.signOut();
});

byId('cancel-recovery').addEventListener('click', () => setRecoveryVisible(false));
byId('sign-out').addEventListener('click', () => client.auth.signOut());
byId('refresh').addEventListener('click', loadData);
byId('place-cancel').addEventListener('click', resetPlaceForm);
byId('promotion-cancel').addEventListener('click', resetPromotionForm);
document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => {
  document.querySelectorAll('.tab').forEach((item) => item.classList.toggle('active', item === tab));
  for (const section of ['places', 'promotions', 'applications', 'reports', 'admins']) {
    byId(`${section}-section`).hidden = tab.dataset.tab !== section;
  }
}));

client.auth.onAuthStateChange((event, session) => {
  if (event === 'PASSWORD_RECOVERY') {
    setRecoveryVisible(true);
    authPanel.hidden = false;
    workspace.hidden = true;
    byId('account-bar').hidden = true;
    notice(authMessage, 'Choose a new password to finish resetting your account.');
    return;
  }
  queueMicrotask(() => {
    if (!recoveryMode) void showSession(session);
  });
});

const { data: sessionData, error: sessionError } = await client.auth.getSession();
if (sessionError) notice(authMessage, sessionError.message, true);
else if (!recoveryMode) await showSession(sessionData.session);
