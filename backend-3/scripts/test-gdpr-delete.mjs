// Тест каскадного удаления пользователя на живой базе (после миграции
// 20260726120000_moderation_gdpr_indexes). Создаёт двух временных
// пользователей со связями (комната, сообщения, DM, дружба, жалоба),
// удаляет одного через prisma.user.delete и проверяет отсутствие FK-ошибок
// и осиротевших строк. Всё временное подчищается.
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const tag = `gdprtest_${Date.now()}`;

async function main() {
  // Уборка остатков предыдущих прогонов (каскад заберёт их комнаты/сообщения).
  await prisma.user.deleteMany({ where: { username: { startsWith: "gdprtest_" } } });
  const u1 = await prisma.user.create({
    data: { username: `${tag}_a`, email: `${tag}_a@test.plink`, password: 'x'.repeat(60) },
  });
  const u2 = await prisma.user.create({
    data: { username: `${tag}_b`, email: `${tag}_b@test.plink`, password: 'x'.repeat(60) },
  });

  const room = await prisma.room.create({
    data: { name: `${tag} room`, hostID: u1.id, hostName: u1.username, code: tag.slice(-6).toUpperCase() },
  });
  await prisma.roomParticipant.create({ data: { roomID: room.id, userID: u1.id } });
  await prisma.chatMessage.create({ data: { roomID: room.id, senderID: u1.id, text: 'hi' } });
  await prisma.directMessage.create({ data: { senderID: u1.id, receiverID: u2.id, content: 'dm' } });
  await prisma.directMessage.create({ data: { senderID: u2.id, receiverID: u1.id, content: 'dm2' } });
  await prisma.friendship.create({ data: { userID: u1.id, friendID: u2.id } });
  await prisma.report.create({ data: { reporterID: u1.id, roomID: room.id, reason: 'test', targetType: 'room', targetID: room.id } });
  await prisma.watchHistory.create({ data: { userID: u1.id, roomID: room.id, mediaTitle: 't' } });

  console.log('created:', { u1: u1.id, u2: u2.id, room: room.id });

  // Главная проверка: удаление не должно упасть по внешнему ключу.
  await prisma.user.delete({ where: { id: u1.id } });
  console.log('user.delete: OK (без ошибок FK)');

  const leftovers = {
    rooms: await prisma.room.count({ where: { hostID: u1.id } }),
    chatMsgs: await prisma.chatMessage.count({ where: { senderID: u1.id } }),
    dms: await prisma.directMessage.count({ where: { OR: [{ senderID: u1.id }, { receiverID: u1.id }] } }),
    friendships: await prisma.friendship.count({ where: { OR: [{ userID: u1.id }, { friendID: u1.id }] } }),
    reports: await prisma.report.count({ where: { reporterID: u1.id } }),
    participants: await prisma.roomParticipant.count({ where: { userID: u1.id } }),
  };
  console.log('осиротевшие строки (должны быть нули):', leftovers);

  // Уборка второго пользователя (каскад заберёт его DM).
  await prisma.user.delete({ where: { id: u2.id } });
  console.log('cleanup: OK');

  const bad = Object.entries(leftovers).filter(([, v]) => v > 0);
  if (bad.length) {
    console.error('ПРОВАЛ: остались строки:', bad);
    process.exit(1);
  }
  console.log('ТЕСТ ПРОЙДЕН: каскадное удаление работает.');
}

main().finally(() => prisma.$disconnect());
