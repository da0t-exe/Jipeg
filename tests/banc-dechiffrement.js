// Fait tourner l'effet de texte de la page sur une horloge qu'on avance image
// par image.
//
// Il faut un banc parce que l'effet est inobservable dans un navigateur pilote :
// il tourne sur requestAnimationFrame, qui ne s'execute pas dans un onglet qui
// ne rend pas, et dechiffrer() refuse de demarrer quand document.hidden est
// vrai - ce qui est le cas du panneau d'apercu. Le garde fait son travail, et
// empeche du meme coup de regarder.
//
// La fonction n'est pas recopiee ici : elle est extraite de docs/index.html a
// chaque execution. Une copie aurait derive des la premiere retouche.
//
//   node tests/banc-dechiffrement.js

'use strict';
const fs = require('fs');
const path = require('path');

const PAGE = path.join(__dirname, '..', 'docs', 'index.html');
const page = fs.readFileSync(PAGE, 'utf8');

function extraire(depuis, jusqua, quoi) {
  const i = page.indexOf(depuis);
  if (i < 0) { throw new Error('introuvable dans la page : ' + quoi); }
  const j = page.indexOf(jusqua, i);
  if (j < 0) { throw new Error('fin introuvable : ' + quoi); }
  return page.slice(i, j + jusqua.length);
}

const source = [
  extraire("var SYMBOLES = '", "';", 'le jeu de symboles'),
  extraire('var TEMPS =', ';', 'la duree commune'),
  extraire('var PAS =', ';', 'le pas'),
  extraire('function dechiffrer(el, duree) {', '}, duree + 600);\n}', 'dechiffrer')
].join('\n\n');

// L'environnement minimal dont la fonction a besoin, et une horloge a nous.
let horloge = 0;
let file = [];
const bac = {
  SYMBOLES: null,
  TEMPS: null,
  PAS: null,
  mouvementReduit: false,
  document: { hidden: false },
  requestAnimationFrame: (f) => file.push(f),
  cancelAnimationFrame: () => {},
  setTimeout: () => {},
  clearTimeout: () => {},
  Math: Math
};
const vm = require('vm');
vm.createContext(bac);
vm.runInContext(source, bac);

function essai(nom, reduit, vrai) {
  bac.mouvementReduit = reduit;
  const el = { textContent: vrai, rythme: null, filet: null };
  horloge = 0;
  file = [];
  bac.requestAnimationFrame = (f) => file.push(f);

  const etats = [];
  let precedent = null;
  let tirages = 0;
  let precQueue = null;

  bac.dechiffrer(el);
  for (let img = 0; img < 400 && file.length; img++) {
    const f = file.shift();
    horloge += 1000 / 60;
    f(horloge);
    if (el.textContent !== precedent) { etats.push(el.textContent); precedent = el.textContent; }
    if (el.textContent !== vrai) {
      const queue = el.textContent.slice(-8);
      if (queue !== precQueue) { tirages++; precQueue = queue; }
    }
  }

  const duree = Math.round(horloge);
  console.log('  ' + nom);
  console.log('    ' + vrai.length + ' caracteres -> ' + duree + ' ms  (attendu '
              + bac.TEMPS + ' ms, quelle que soit la longueur)');
  console.log('    etats traverses : ' + etats.length + '   tirages de brouillon : ' + tirages);
  console.log('    milieu : ' + (etats[Math.floor(etats.length / 2)] || '-'));
  console.log('    exact a l arrivee : ' + (el.textContent === vrai ? 'oui' : 'NON'));
  return { duree, tirages, exact: el.textContent === vrai };
}

console.log('  duree lue dans la page : TEMPS = ' + bac.TEMPS + ' ms, PAS = ' + bac.PAS + ' ms');
console.log('');
const a = essai('mouvement normal   (brouillon retire a chaque image)', false, 'It comes back lighter.');
console.log('');
const b = essai('mouvement reduit   (brouillon retire 8 fois par seconde)', true, 'It comes back lighter.');
console.log('');
const c = essai('ligne longue       (meme duree, elle defile juste plus vite)', false,
                'Windows 10 and 11, no administrator rights');

const soucis = [];
if (!a.exact || !b.exact || !c.exact) { soucis.push('une ligne n arrive pas sur son texte exact'); }
if (b.tirages >= a.tirages) { soucis.push('le mouvement reduit ne calme pas le brouillon'); }
for (const [nom, r] of [['courte', a], ['reduite', b], ['longue', c]]) {
  if (Math.abs(r.duree - bac.TEMPS) > 40) {
    soucis.push('la ligne ' + nom + ' dure ' + r.duree + ' ms au lieu de ' + bac.TEMPS);
  }
}

console.log(soucis.length ? '  ' + soucis.join('\n  ') : '  banc conforme');
process.exit(soucis.length ? 1 : 0);
