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
let dashboardCounts = { places: null, promotions: null, applications: null, reports: null, activePromotions: null, pendingApplications: null, openReports: null };
let sessionGeneration = 0;
let activeAdminId = null;

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

function friendlyAuthError(error) {
  const message = String(error?.message ?? '');
  if (error?.code === 'invalid_credentials' || /invalid login credentials/i.test(message)) {
    return 'Email or password is incorrect. Check your credentials or use password recovery.';
  }
  if (error?.code === 'email_not_confirmed' || /email not confirmed/i.test(message)) {
    return 'Confirm your email address before signing in.';
  }
  if (/too many requests/i.test(message)) {
    return 'Too many sign-in attempts. Wait a few minutes, then try again.';
  }
  if (/failed to fetch|networkerror/i.test(message)) {
    return 'Could not reach Supabase. Check your connection and the configured project URL.';
  }
  return message || 'Sign-in failed. Please try again.';
}

async function showSession(session) {
  const generation = ++sessionGeneration;
  if (!session) {
    activeAdminId = null;
    authPanel.hidden = false;
    workspace.hidden = true;
    byId('account-bar').hidden = true;
    return;
  }

  if (activeAdminId === session.user.id && !workspace.hidden) return;
  try {
    const { data: profile, error } = await client
      .from('profiles')
      .select('role')
      .eq('id', session.user.id)
      .maybeSingle();
    if (generation !== sessionGeneration) return;
    if (error) {
      notice(authMessage, `You signed in, but administrator access could not be verified: ${error.message}`, true);
      return;
    }
    if (profile?.role !== 'admin') {
      byId('first-admin-help').open = true;
      notice(authMessage, 'You signed in, but this account does not have the administrator role. Follow the first-administrator setup instructions below, then sign in again.', true);
      await client.auth.signOut();
      return;
    }

    activeAdminId = session.user.id;
    authPanel.hidden = true;
    workspace.hidden = false;
    byId('account-bar').hidden = false;
    byId('account-email').textContent = session.user.email ?? '';
    await loadData();
  } catch (error) {
    if (generation === sessionGeneration) {
      notice(authMessage, `Could not verify this administrator session: ${friendlyAuthError(error)}`, true);
    }
  }
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

function renderBars(container, entries, emptyMessage) {
  if (entries.length === 0) {
    container.innerHTML = `<p class="empty">${escapeHtml(emptyMessage)}</p>`;
    return;
  }
  const maximum = Math.max(...entries.map((entry) => entry.value), 1);
  container.innerHTML = entries.map((entry) => `
    <div class="bar-row">
      <span class="bar-label" title="${escapeHtml(entry.label)}">${escapeHtml(entry.label)}</span>
      <span class="bar-track"><span class="bar-fill" style="--bar-width:${Math.round(entry.value / maximum * 100)}%"></span></span>
      <span class="bar-value">${entry.value}</span>
    </div>`).join('');
}

function renderDashboard() {
  const activePromotions = promotions.filter((promotion) =>
    promotion.active && new Date(promotion.starts_at) <= new Date() && new Date(promotion.ends_at) > new Date());
  const pendingApplications = applications.filter((application) => application.status === 'Pending review');
  const openReports = reports.filter((report) => report.status === 'Open');
  byId('metric-places').textContent = dashboardCounts.places ?? '—';
  byId('metric-promotions').textContent = dashboardCounts.activePromotions ?? activePromotions.length;
  byId('metric-applications').textContent = dashboardCounts.pendingApplications ?? pendingApplications.length;
  byId('metric-reports').textContent = dashboardCounts.openReports ?? openReports.length;

  const now = new Date();
  const months = Array.from({ length: 6 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - (5 - index), 1);
    return {
      key: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`,
      label: date.toLocaleString(undefined, { month: 'short' }),
      value: 0,
    };
  });
  const monthByKey = new Map(months.map((month) => [month.key, month]));
  for (const report of reports) {
    const date = new Date(report.created_at);
    if (Number.isNaN(date.getTime())) continue;
    const month = monthByKey.get(`${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`);
    if (month) month.value += 1;
  }
  renderBars(byId('report-trend'), months, 'No report history is available.');

  const placeStatuses = new Map();
  for (const place of places) placeStatuses.set(place.status || 'Unknown', (placeStatuses.get(place.status || 'Unknown') ?? 0) + 1);
  renderBars(byId('place-breakdown'), [...placeStatuses].map(([label, value]) => ({ label, value })), 'No place records are available.');

  const applicationStatuses = new Map();
  for (const application of applications) {
    const label = application.status || 'Unknown';
    applicationStatuses.set(label, (applicationStatuses.get(label) ?? 0) + 1);
  }
  renderBars(byId('application-breakdown'), [...applicationStatuses].map(([label, value]) => ({ label, value })), 'No business applications are available.');

  const reportCountsByPlace = new Map();
  for (const report of reports) {
    const place = places.find((item) => item.id === report.place_id);
    const label = place?.name ?? 'Place unavailable';
    reportCountsByPlace.set(label, (reportCountsByPlace.get(label) ?? 0) + 1);
  }
  const topPlaces = [...reportCountsByPlace].sort((a, b) => b[1] - a[1]).slice(0, 5);
  const topPlacesContainer = byId('top-reported-places');
  topPlacesContainer.innerHTML = topPlaces.length
    ? topPlaces.map(([name, count]) => `
      <article class="record">
        <div><h3>${escapeHtml(name)}</h3><p>${count} report${count === 1 ? '' : 's'}</p></div>
        <span class="count">${count}</span>
      </article>`).join('')
    : '<p class="empty">There are no place reports.</p>';
}

function renderPlaceOptions(selectedId = '') {
  const select = promotionForm.elements.place_id;
  select.innerHTML = '<option value="">Select a place</option>' + places.map((place) =>
    `<option value="${escapeHtml(place.id)}">${escapeHtml(place.name)}</option>`).join('');
  select.value = selectedId;
}

async function loadData() {
  notice(workspaceMessage, 'Loading database records…');
  let results;
  try {
    results = await Promise.all([
      client.from('places').select('*', { count: 'exact' }).order('name'),
      client.from('promotions').select('*', { count: 'exact' }).order('starts_at', { ascending: false }),
      client.from('business_applications').select('*', { count: 'exact' }).order('created_at', { ascending: false }),
      client.from('reports').select('*', { count: 'exact' }).order('created_at', { ascending: false }),
      client.from('promotions').select('id', { count: 'exact', head: true }).eq('active', true).lte('starts_at', new Date().toISOString()).gt('ends_at', new Date().toISOString()),
      client.from('business_applications').select('id', { count: 'exact', head: true }).eq('status', 'Pending review'),
      client.from('reports').select('id', { count: 'exact', head: true }).eq('status', 'Open'),
    ]);
  } catch (error) {
    notice(workspaceMessage, `Could not connect to the app database: ${friendlyAuthError(error)}`, true);
    return;
  }
  const [placeResult, promotionResult, applicationResult, reportResult, activePromotionCount, pendingApplicationCount, openReportCount] = results;
  const warnings = [];
  const datasets = [
    ['Places', placeResult, 'places'],
    ['Promotions', promotionResult, 'promotions'],
    ['Business applications', applicationResult, 'applications'],
    ['Reports', reportResult, 'reports'],
  ];
  for (const [label, result, key] of datasets) {
    if (result.error) {
      warnings.push(`${label}: ${result.error.message}`);
      dashboardCounts[key] = null;
    } else {
      dashboardCounts[key] = result.count;
    }
  }
  if (!placeResult.error) places = placeResult.data ?? [];
  if (!promotionResult.error) promotions = promotionResult.data ?? [];
  if (!applicationResult.error) applications = applicationResult.data ?? [];
  if (!reportResult.error) reports = reportResult.data ?? [];
  dashboardCounts.activePromotions = activePromotionCount.error ? null : activePromotionCount.count;
  dashboardCounts.pendingApplications = pendingApplicationCount.error ? null : pendingApplicationCount.count;
  dashboardCounts.openReports = openReportCount.error ? null : openReportCount.count;
  for (const [label, result] of [
    ['Active promotions', activePromotionCount],
    ['Pending applications', pendingApplicationCount],
    ['Open reports', openReportCount],
  ]) {
    if (result.error) warnings.push(`${label} count: ${result.error.message}`);
  }
  renderPlaces();
  renderPlaceOptions();
  renderPromotions();
  renderApplications();
  renderReports();
  renderDashboard();
  notice(workspaceMessage, warnings.length
    ? `Some dashboard data could not be loaded. ${warnings.join(' · ')}`
    : '');
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
  const formElement = event.currentTarget;
  setBusy(formElement, true);
  notice(authMessage);
  const form = new FormData(formElement);
  try {
    const { data, error } = await client.auth.signInWithPassword({
      email: String(form.get('email')).trim(),
      password: form.get('password'),
    });
    if (error) {
      notice(authMessage, friendlyAuthError(error), true);
      return;
    }
    await showSession(data.session);
  } catch (error) {
    notice(authMessage, friendlyAuthError(error), true);
  } finally {
    setBusy(formElement, false);
  }
});

byId('forgot-link').addEventListener('click', async () => {
  const email = String(byId('login-form').elements.email.value).trim();
  if (!email) {
    notice(authMessage, 'Enter your email address first.', true);
    return;
  }
  const redirectTo = new URL(window.location.pathname, window.location.origin).toString();
  try {
    const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo });
    notice(authMessage, error
      ? `Could not send the reset email: ${error.message}`
      : 'If the account exists, a secure password reset link will arrive in your inbox.', Boolean(error));
  } catch (error) {
    notice(authMessage, `Could not send the reset email: ${friendlyAuthError(error)}`, true);
  }
});

byId('recovery-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const formElement = event.currentTarget;
  const form = new FormData(formElement);
  const password = String(form.get('password'));
  if (password !== form.get('confirmation')) {
    notice(authMessage, 'The passwords do not match.', true);
    return;
  }
  setBusy(formElement, true);
  try {
    const { error } = await client.auth.updateUser({ password });
    if (error) {
      notice(authMessage, `Could not update password: ${error.message}`, true);
      return;
    }
    setRecoveryVisible(false);
    notice(authMessage, 'Password updated. Sign in with your new password.');
    await client.auth.signOut();
  } catch (error) {
    notice(authMessage, `Could not update password: ${friendlyAuthError(error)}`, true);
  } finally {
    setBusy(formElement, false);
  }
});

byId('cancel-recovery').addEventListener('click', () => setRecoveryVisible(false));
byId('sign-out').addEventListener('click', () => client.auth.signOut());
byId('refresh').addEventListener('click', loadData);
byId('place-cancel').addEventListener('click', resetPlaceForm);
byId('promotion-cancel').addEventListener('click', resetPromotionForm);
document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => {
  document.querySelectorAll('.tab').forEach((item) => item.classList.toggle('active', item === tab));
  for (const section of ['dashboard', 'places', 'promotions', 'applications', 'reports', 'admins']) {
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
