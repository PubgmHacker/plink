// Тест грант-пути веб-подписки (webpay.ts → grantWebPremium) на живой БД.
// Проверяет: выдачу премиума, продление от конца текущей подписки,
// идемпотентность по paymentId, и что entitlements-семантика совпадает
// с той, что читает приложение (isPremium + premiumUntil).
import { PrismaClient } from '@prisma/client';
import { grantWebPremium } from '../dist/routes/webpay.js';

const prisma = new PrismaClient();
const tag = `webplus${Date.now().toString(36)}`;
let failures = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? '✅' : '❌'} ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
};

const u = await prisma.user.create({
  data: { username: tag, email: `${tag}@test.plink`, password: 'x'.repeat(60) },
});

// 1. Первый платёж: месяц.
const r1 = await grantWebPremium(u.id, '1m', 'pay-test-1');
let user = await prisma.user.findUnique({ where: { id: u.id } });
const now = Date.now();
const days = (ms) => Math.round((ms - now) / 86400000);
check('Первый платёж выдал премиум', r1 === 'granted' && user.isPremium === true);
check(
  'Срок ≈ 30 дней',
  days(user.premiumUntil.getTime()) === 30,
  `${days(user.premiumUntil.getTime())} дн`,
);

// 2. Повторный вебхук того же платежа — не должен продлить.
const r2 = await grantWebPremium(u.id, '1m', 'pay-test-1');
user = await prisma.user.findUnique({ where: { id: u.id } });
check(
  'Дубликат вебхука проигнорирован',
  r2 === 'duplicate' && days(user.premiumUntil.getTime()) === 30,
);

// 3. Второй платёж: продление копится (30 + 90 = 120 дней).
const r3 = await grantWebPremium(u.id, '3m', 'pay-test-2');
user = await prisma.user.findUnique({ where: { id: u.id } });
check(
  'Продление считается от конца подписки',
  r3 === 'granted' && days(user.premiumUntil.getTime()) === 120,
  `${days(user.premiumUntil.getTime())} дн`,
);

// 4. Семантика entitlements (та же формула, что в billing.ts / приложении).
const active = user.isPremium && (!user.premiumUntil || user.premiumUntil > new Date());
check('Приложение увидит premium (entitlements-формула)', active === true);

const subs = await prisma.subscription.count({ where: { userID: u.id } });
check('Записей Subscription: 2', subs === 2, String(subs));

await prisma.user.delete({ where: { id: u.id } });
console.log(failures === 0 ? '\nГРАНТ-ПУТЬ РАБОТАЕТ' : `\nПРОВАЛОВ: ${failures}`);
await prisma.$disconnect();
process.exit(failures === 0 ? 0 : 1);
