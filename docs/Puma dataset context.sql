SELECT COUNT(*) AS total
FROM puma_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id
WHERE v.uid = {{uid}}
  AND v.node_id = {{targetNode}}
  AND p.code = 'user.create'





/** Arbre du contexte choisi : le noeud du token est l'unique racine. */
public List<NodeDto> contextSubtree(String contextNode, String applicationId) {
    if (contextNode == null) {
        return List.of();
    }
    List<String> roots = List.of(contextNode);
    if (applicationId == null || applicationId.isBlank()) {
        return hierarchy.getSubtree(roots);
    }
    return hierarchy.getSubtreeForApplication(roots, applicationId);
}


-- =====================================================================
-- PUMA : jeu de données de démonstration
-- Quatre applications : PUMA, Partner Portal, Mobility Hub, Rataweb
-- PUMA porte l'administration des utilisateurs. Elle n'est disponible
-- que sur Roller 2 et Roller 5 : on ne peut créer des utilisateurs que
-- sur ces deux regroupements et leurs vendors.
-- Identifiants opaques (A = application, P = permission, R = rôle).
-- Rejouable : chaque instruction est idempotente.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Index uniques (nécessaires aux ON CONFLICT, à reporter dans schema.sql)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_role_permission ON role_permission (role_id, permission_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_node_application ON node_application (node_id, application_id);

DELETE FROM assignment a USING puma_user u
WHERE a.user_id = u.id AND u.uid = 'thomas.martin' AND a.role_id IN ('R1', 'R4');
-- ---------------------------------------------------------------------
-- 1. Applications
-- ---------------------------------------------------------------------
INSERT INTO application (id, name) VALUES
  ('A0', 'PUMA'),
  ('A1', 'Partner Portal'),
  ('A2', 'Mobility Hub'),
  ('A3', 'Rataweb')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;


-- ---------------------------------------------------------------------
-- 2. Permissions
--    code : identifiant technique lu par les règles d'autorisation
--    label : libellé affiché
--    application_id : conservé pour compatibilité, non utilisé par les règles
-- ---------------------------------------------------------------------
INSERT INTO permission (id, code, label, application_id) VALUES
  -- PUMA : administration des utilisateurs
  ('P01', 'user.create',         'Créer un utilisateur',                 'A0'),
  ('P02', 'user.delete',         'Supprimer un utilisateur',             'A0'),
  ('P03', 'user.deactivate',     'Désactiver un utilisateur',            'A0'),
  ('P04', 'user.reactivate',     'Réactiver un utilisateur',             'A0'),
  ('P05', 'user.list',           'Consulter les utilisateurs',           'A0'),
  ('P07', 'app.assign',          'Attribuer des applications',           'A0'),
  ('P22', 'role.assign',         'Attribuer des rôles',                  'A0'),
  -- Partner Portal
  ('P06', 'user.update.contact', 'Modifier ses coordonnées',             'A1'),
  ('P08', 'message.read',        'Lire la messagerie',                   'A1'),
  ('P09', 'message.secret.read', 'Lire les identifiants confidentiels',  'A1'),
  ('P10', 'checklist.read',      'Consulter la checklist',               'A1'),
  ('P11', 'checklist.edit',      'Modifier la checklist',                'A1'),
  -- Mobility Hub
  ('P12', 'stocklist.read',      'Consulter le stock',                   'A2'),
  ('P13', 'stocklist.download',  'Télécharger la liste du stock',        'A2'),
  ('P14', 'contract.read',       'Consulter un contrat',                 'A2'),
  ('P15', 'contract.create',     'Créer un contrat',                     'A2'),
  ('P16', 'contract.approve',    'Approuver un contrat',                 'A2'),
  ('P17', 'customer.edit',       'Modifier les données client',          'A2'),
  -- Rataweb (hypothèse : saisie et suivi des demandes de financement)
  ('P18', 'quote.read',          'Consulter un devis',                   'A3'),
  ('P19', 'quote.create',        'Créer un devis',                       'A3'),
  ('P20', 'request.submit',      'Soumettre une demande de financement', 'A3'),
  ('P21', 'request.approve',     'Approuver une demande de financement', 'A3')
ON CONFLICT (id) DO UPDATE SET
  code = EXCLUDED.code, label = EXCLUDED.label, application_id = EXCLUDED.application_id;


-- ---------------------------------------------------------------------
-- 3. Rôles globaux (node_id et parent_role_id vides)
-- ---------------------------------------------------------------------
INSERT INTO app_role (id, name, application_id, parent_role_id, node_id) VALUES
  -- PUMA
  ('R20', 'Administrateur PUMA',            'A0', NULL, NULL),
  ('R21', 'Gestionnaire des utilisateurs',  'A0', NULL, NULL),
  ('R22', 'Consultation des utilisateurs',  'A0', NULL, NULL),
  -- Partner Portal
  ('R10', 'Administrateur partenaire',      'A1', NULL, NULL),
  ('R11', 'Vendeur intérimaire',            'A1', NULL, NULL),
  ('R12', 'Responsable de point de vente',  'A1', NULL, NULL),
  -- Mobility Hub
  ('R13', 'Vendeur',                        'A2', NULL, NULL),
  ('R14', 'Responsable des ventes',         'A2', NULL, NULL),
  -- Rataweb
  ('R15', 'Conseiller financement',         'A3', NULL, NULL),
  ('R16', 'Superviseur financement',        'A3', NULL, NULL)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, application_id = EXCLUDED.application_id;


-- ---------------------------------------------------------------------
-- 4. Rôles spécialisés : une seule famille, pour la démonstration
--    Vendeur Mobility Hub, restreint sur l'union JLR, puis sur un vendor
-- ---------------------------------------------------------------------
INSERT INTO app_role (id, name, application_id, parent_role_id, node_id) VALUES
  ('R17', 'Vendeur JLR',             'A2', 'R13', '9305574'),
  ('R18', 'Vendeur JLR Traunstein',  'A2', 'R17', '2672756')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;


-- ---------------------------------------------------------------------
-- 5. Permissions des rôles
--    Rôle global : granted = true pour chaque permission accordée
--    Rôle spécialisé : uniquement les retraits, granted = false
-- ---------------------------------------------------------------------

-- Nettoyage de la version précédente : l'administration a quitté Partner Portal
DELETE FROM role_permission
WHERE role_id = 'R10' AND permission_id IN ('P01', 'P02', 'P03', 'P04', 'P05', 'P07');
DELETE FROM role_permission
WHERE role_id = 'R12' AND permission_id = 'P05';

INSERT INTO role_permission (role_id, permission_id, granted) VALUES
  -- Administrateur PUMA : toute l'administration des utilisateurs
  ('R20', 'P01', true), ('R20', 'P02', true), ('R20', 'P03', true),
  ('R20', 'P04', true), ('R20', 'P05', true), ('R20', 'P07', true),
  ('R20', 'P22', true),

  -- Gestionnaire des utilisateurs : créer et gérer, sans supprimer
  ('R21', 'P01', true), ('R21', 'P03', true), ('R21', 'P04', true),
  ('R21', 'P05', true), ('R21', 'P22', true),

  -- Consultation des utilisateurs : lecture seule
  ('R22', 'P05', true),

  -- Administrateur partenaire : fonctions du portail
  ('R10', 'P06', true), ('R10', 'P08', true), ('R10', 'P09', true),
  ('R10', 'P10', true), ('R10', 'P11', true),

  -- Vendeur intérimaire : ses propres coordonnées et la messagerie
  ('R11', 'P06', true), ('R11', 'P08', true),

  -- Responsable de point de vente : messagerie et checklist
  ('R12', 'P08', true), ('R12', 'P10', true),

  -- Vendeur Mobility Hub
  ('R13', 'P12', true), ('R13', 'P13', true), ('R13', 'P14', true),
  ('R13', 'P15', true), ('R13', 'P17', true),

  -- Responsable des ventes : tout le vendeur, plus l'approbation
  ('R14', 'P12', true), ('R14', 'P13', true), ('R14', 'P14', true),
  ('R14', 'P15', true), ('R14', 'P16', true), ('R14', 'P17', true),

  -- Vendeur JLR : pas de modification des données client (illustratif)
  ('R17', 'P17', false),

  -- Vendeur JLR Traunstein : pas de téléchargement du stock (PDF Auto Eder)
  ('R18', 'P13', false),

  -- Conseiller financement
  ('R15', 'P18', true), ('R15', 'P19', true), ('R15', 'P20', true),

  -- Superviseur financement
  ('R16', 'P18', true), ('R16', 'P19', true), ('R16', 'P20', true), ('R16', 'P21', true)
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- ---------------------------------------------------------------------
-- 6. Disponibilité des applications par noeud
--    Déclarée sur chaque noeud d'un sous-arbre, à partir de sa racine.
-- ---------------------------------------------------------------------

-- PUMA : uniquement Roller 2 et Roller 5, et leurs vendors
WITH RECURSIVE sub AS (
    SELECT CAST(v.root AS varchar) AS node_id
    FROM (VALUES ('9200002'), ('9200005')) AS v(root)
  UNION
    SELECT np.node_id FROM node_parent np JOIN sub s ON np.parent_id = s.node_id
)
INSERT INTO node_application (node_id, application_id)
SELECT node_id, 'A0' FROM sub
ON CONFLICT (node_id, application_id) DO NOTHING;

-- Partner Portal : tous les partenaires
WITH RECURSIVE sub AS (
    SELECT CAST(v.root AS varchar) AS node_id
    FROM (VALUES ('9300001'), ('9305574'), ('9305616'), ('9305707')) AS v(root)
  UNION
    SELECT np.node_id FROM node_parent np JOIN sub s ON np.parent_id = s.node_id
)
INSERT INTO node_application (node_id, application_id)
SELECT node_id, 'A1' FROM sub
ON CONFLICT (node_id, application_id) DO NOTHING;

-- Mobility Hub : les réseaux automobiles et la branche Roller GmbH
WITH RECURSIVE sub AS (
    SELECT CAST(v.root AS varchar) AS node_id
    FROM (VALUES ('9305574'), ('9305616'), ('9305707'), ('9100002')) AS v(root)
  UNION
    SELECT np.node_id FROM node_parent np JOIN sub s ON np.parent_id = s.node_id
)
INSERT INTO node_application (node_id, application_id)
SELECT node_id, 'A2' FROM sub
ON CONFLICT (node_id, application_id) DO NOTHING;

-- Rataweb : toute l'union Roller et l'union JLR
WITH RECURSIVE sub AS (
    SELECT CAST(v.root AS varchar) AS node_id
    FROM (VALUES ('9300001'), ('9305574')) AS v(root)
  UNION
    SELECT np.node_id FROM node_parent np JOIN sub s ON np.parent_id = s.node_id
)
INSERT INTO node_application (node_id, application_id)
SELECT node_id, 'A3' FROM sub
ON CONFLICT (node_id, application_id) DO NOTHING;


-- ---------------------------------------------------------------------
-- 7. Affectations de thomas.martin (utilisateur existant, affectations
--    existantes conservées)
--    Tous les rôles globaux sur Roller 2 et Roller 5. La vue ne retient
--    pour chaque noeud que les rôles dont l'application y est disponible.
-- ---------------------------------------------------------------------
INSERT INTO assignment (user_id, role_id, node_id)
SELECT u.id, r.id, n.node_id
FROM puma_user u
CROSS JOIN (VALUES ('9200002'), ('9200005')) AS n(node_id)
JOIN app_role r ON r.node_id IS NULL
               AND r.id IN ('R10', 'R11', 'R12', 'R13', 'R14', 'R15', 'R16', 'R20', 'R21', 'R22')
WHERE u.uid = 'thomas.martin'
ON CONFLICT (user_id, role_id, node_id) DO NOTHING;

-- Démonstration de la spécialisation : Thomas vendeur Mobility Hub
-- sur deux vendors JLR voisins (l'exemple de Philip)
INSERT INTO assignment (user_id, role_id, node_id)
SELECT u.id, 'R13', v.node_id
FROM puma_user u
CROSS JOIN (VALUES ('2672749'), ('2672756')) AS v(node_id)
WHERE u.uid = 'thomas.martin'
ON CONFLICT (user_id, role_id, node_id) DO NOTHING;


-- =====================================================================
-- Résultats attendus pour thomas.martin
--
-- Contexte K (2602700, sous Roller 2) :
--   PUMA, Partner Portal et Rataweb. Pas de Mobility Hub (non disponible
--   sur la branche Roller GmbH & Co. KG).
--
-- Contexte 2700010 (sous Roller 5) :
--   PUMA, Partner Portal, Mobility Hub et Rataweb.
--
-- Contexte 2672749 (JLR) : Vendeur Mobility Hub uniquement.
--   Spécialisation la plus proche = Vendeur JLR :
--   consulter et télécharger le stock, consulter et créer un contrat.
--
-- Contexte 2672756 (JLR Traunstein) : Vendeur Mobility Hub uniquement.
--   Spécialisation la plus proche = Vendeur JLR Traunstein :
--   consulter le stock, consulter et créer un contrat.
-- =====================================================================
