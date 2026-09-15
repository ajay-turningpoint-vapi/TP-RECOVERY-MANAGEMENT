/**
 * Branch registry — one entry per company/branch, each backed by its own
 * BUSY (MSSQL) company database. Some branches live on a different SQL
 * Server entirely, so a branch may override any of server/port/user/
 * password; anything it doesn't set inherits the shared DB_* defaults
 * from .env (see config/mssql.ts baseConfig).
 *
 * Env shape:
 *
 *   BRANCHES=vapi,valsad,daman
 *
 *   # same server as DB_*, only the database + parent groups differ
 *   BRANCH_vapi_LABEL=Vapi
 *   BRANCH_vapi_DATABASE=BusyComp0018_db12026
 *   BRANCH_vapi_PARENTGRP=574140,574141,258335,577533
 *
 *   # different server — give it its own address/credentials
 *   BRANCH_daman_LABEL=Daman
 *   BRANCH_daman_SERVER=192.168.5.20\SQL2019
 *   BRANCH_daman_PORT=1433
 *   BRANCH_daman_USER=sa
 *   BRANCH_daman_PASSWORD=Daman@123
 *   BRANCH_daman_DATABASE=BusyComp0031_db12026
 *   BRANCH_daman_PARENTGRP=661200,661201
 *
 * If BRANCHES is unset the registry falls back to a single branch built
 * from the existing DB_DATABASE + the parent-group codes that were
 * previously hardcoded in customerReport.mssql.sql, so nothing breaks
 * before the env is populated.
 */
import 'dotenv/config';
import logger from '../utils/logger';

export interface Branch {
  /** Stable id used in the API (?branch=<id>) and as customer_ageing_snapshot.branch_id. */
  id: string;
  /** Human label for the RE dropdown. */
  label: string;
  /** BUSY company database name for this branch. */
  database: string;
  /** MASTER1.PARENTGRP codes that scope this branch's debtor accounts. */
  parentGrpCodes: string[];
  /** Per-branch connection overrides — undefined means "use the shared DB_* default". */
  server?: string;
  port?: number;
  user?: string;
  password?: string;
}

/** Codes that were hardcoded in customerReport.mssql.sql before this change. */
const LEGACY_PARENTGRP_CODES = ['574140', '574141', '258335', '577533'];

function parseCsv(raw: string | undefined): string[] {
  return (raw || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function readBranch(id: string): Branch {
  const prefix = `BRANCH_${id}_`;
  const database = process.env[`${prefix}DATABASE`];
  const parentGrpCodes = parseCsv(process.env[`${prefix}PARENTGRP`]);

  if (!database) {
    throw new Error(`Branch "${id}" is listed in BRANCHES but ${prefix}DATABASE is not set.`);
  }
  if (parentGrpCodes.length === 0) {
    throw new Error(`Branch "${id}" is listed in BRANCHES but ${prefix}PARENTGRP is empty.`);
  }

  const portRaw = process.env[`${prefix}PORT`];

  return {
    id,
    label: process.env[`${prefix}LABEL`] || id,
    database,
    parentGrpCodes,
    server: process.env[`${prefix}SERVER`] || undefined,
    port: portRaw ? parseInt(portRaw, 10) : undefined,
    user: process.env[`${prefix}USER`] || undefined,
    password: process.env[`${prefix}PASSWORD`] || undefined,
  };
}

function buildRegistry(): Branch[] {
  const ids = parseCsv(process.env.BRANCHES);

  if (ids.length === 0) {
    const database = process.env.DB_DATABASE || 'BusyComp0018_db12026';
    logger.warn(
      `[branches] BRANCHES is not set — falling back to a single branch "default" (${database}).`
    );
    return [
      {
        id: 'default',
        label: process.env.DEFAULT_BRANCH_LABEL || 'Turning Point',
        database,
        parentGrpCodes: LEGACY_PARENTGRP_CODES,
      },
    ];
  }

  const branches = ids.map(readBranch);
  logger.info(
    `[branches] Loaded ${branches.length} branch(es): ${branches.map((b) => `${b.id}→${b.database}`).join(', ')}`
  );
  return branches;
}

const REGISTRY: Branch[] = buildRegistry();

/** The branch used when a caller doesn't specify one (first configured branch). */
export const DEFAULT_BRANCH_ID: string = REGISTRY[0].id;

export function getBranches(): Branch[] {
  return REGISTRY;
}

export function getBranch(id: string | undefined | null): Branch | undefined {
  if (!id) return undefined;
  return REGISTRY.find((b) => b.id === id);
}

/** Resolve a branch id to a real Branch, defaulting to DEFAULT_BRANCH_ID. Throws on an unknown non-empty id. */
export function resolveBranch(id?: string | null): Branch {
  if (!id || id === DEFAULT_BRANCH_ID) {
    return getBranch(DEFAULT_BRANCH_ID)!;
  }
  const branch = getBranch(id);
  if (!branch) {
    throw new Error(`Unknown branch "${id}". Known branches: ${REGISTRY.map((b) => b.id).join(', ')}.`);
  }
  return branch;
}
