// Le vrai code de la page, sorti tel quel, avec une horloge qu'on avance
// image par image. C'est le seul moyen de l'observer ici : requestAnimationFrame
// ne s'execute pas dans un onglet qui ne rend pas, et document.hidden y est vrai.
var SYMBOLES = '-_~`!@#$%^&*()+=[]{}|;:,.<>?';
var mouvementReduit = false;
var document = { hidden: false };
var horloge = 0, filesAttente = [];
function requestAnimationFrame(f) { filesAttente.push(f); return filesAttente.length; }
function cancelAnimationFrame() {}
function setTimeout() {}
function clearTimeout() {}

function dechiffrer(el, duree) {
  if (!el) { return; }
  // Un onglet en arriere-plan gele les minuteries : le texte resterait fige sur
  // du bruit, ce qui est pire que pas d'animation du tout.
  if (document.hidden) { return; }
  // Une course en cours est annulee avant qu'on lise le texte : sinon on
  // prendrait son bruit pour la verite lors d'un changement de langue.
  if (el.rythme) { cancelAnimationFrame(el.rythme); }
  if (el.filet) { clearTimeout(el.filet); }

  var vrai = el.textContent;
  if (!vrai) { return; }
  duree = duree || 380;

  // Le brouillon derriere le curseur est retire au sort. A chaque image, cela
  // scintille ; c'est la partie de l'effet qui fatigue, bien plus que la
  // revelation elle-meme. En mouvement reduit on ne le retire donc que huit
  // fois par seconde : le texte se resout toujours, mais il ne clignote pas.
  var intervalleBruit = mouvementReduit ? 115 : 0;
  var bruit = '', dernierTirage = -1e9;

  function tirer() {
    var b = '';
    for (var i = 0; i < vrai.length; i++) {
      var c = vrai.charAt(i);
      b += (c === ' ') ? ' ' : SYMBOLES.charAt(Math.floor(Math.random() * SYMBOLES.length));
    }
    return b;
  }

  // Une image du navigateur par ecriture, et pas une minuterie a dix-sept
  // millisecondes : ecrire du texte force un recalcul de mise en page, et le
  // faire hors cadence donne exactement la saccade qu'on cherche a eviter.
  var depart = null;
  function pas(t) {
    if (depart === null) { depart = t; }
    var k = Math.min(1, (t - depart) / duree);
    var montres = Math.round(k * vrai.length);
    if (montres >= vrai.length) {
      el.textContent = vrai;
      el.rythme = null;
      return;
    }
    if (t - dernierTirage >= intervalleBruit) {
      bruit = tirer();
      dernierTirage = t;
    }
    el.textContent = vrai.slice(0, montres) + bruit.slice(montres);
    el.rythme = requestAnimationFrame(pas);
  }
  el.rythme = requestAnimationFrame(pas);

  // Filet : quoi qu'il arrive aux images, le vrai texte est remis.
  el.filet = setTimeout(function () {
    if (el.rythme) { cancelAnimationFrame(el.rythme); el.rythme = null; }
    el.textContent = vrai;
  }, duree + 600);
}

function essai(nom, reduit, vrai) {
  mouvementReduit = reduit;
  var el = { textContent: vrai, rythme: null, filet: null };
  horloge = 0; filesAttente = [];
  var etats = [], precedent = null, tirages = 0, precBruit = null;
  dechiffrer(el, 380);
  for (var img = 0; img < 40 && filesAttente.length; img++) {
    var f = filesAttente.shift();
    horloge += 16.7;
    f(horloge);
    if (el.textContent !== precedent) { etats.push(el.textContent); precedent = el.textContent; }
    var queue = el.textContent.replace(/^[^%]*/, '');
    if (el.textContent !== vrai) {
      var b = el.textContent.slice(-6);
      if (b !== precBruit) { tirages++; precBruit = b; }
    }
  }
  console.log('  ' + nom);
  console.log('    etats traverses : ' + etats.length + '   tirages de brouillon : ' + tirages);
  console.log('    milieu : ' + (etats[Math.floor(etats.length / 2)] || '-'));
  console.log('    final  : ' + el.textContent + '   exact : ' + (el.textContent === vrai));
}

essai('mouvement normal   (tirage a chaque image)', false, 'It comes back lighter.');
essai('mouvement reduit   (tirage 8 fois par seconde)', true, 'It comes back lighter.');
