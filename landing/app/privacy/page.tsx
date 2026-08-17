import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Конфиденциальность — Plink',
  description: 'Политика конфиденциальности Plink',
};

export default function PrivacyPage() {
  return (
    <>
      <header className="border-b border-surface-2">
        <div className="container-main flex h-20 items-center">
          <Link href="/" className="text-display text-2xl font-bold text-text-primary">
            Plink
          </Link>
        </div>
      </header>

      <main className="container-main py-16">
        <h1 className="text-display text-4xl text-text-primary">Политика конфиденциальности</h1>
        <p className="mt-4 text-text-secondary">Последнее обновление: 30 июля 2026</p>

        <div className="mt-12 max-w-3xl space-y-8 text-text-secondary">
          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">
              1. Какие данные мы собираем
            </h2>
            <p>
              Аккаунт: email, имя пользователя, аватар (опционально). Контент: история комнат,
              сообщения чата, реакции. Технические данные: модель устройства, версия iOS, анонимная
              статистика использования.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">
              2. Как мы используем данные
            </h2>
            <p>
              Для работы Сервиса: синхронизация комнат, доставка сообщений, персонализация. Для
              улучшения: анализ сбоев, оптимизация производительности. Мы не продаём ваши данные
              третьим лицам.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">3. Хранение</h2>
            <p>
              Данные хранятся на серверах в ЕС. Сообщения чата — 30 дней, история комнат — 90 дней.
              Вы можете удалить аккаунт и все данные в настройках приложения.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">4. Cookies и аналитика</h2>
            <p>
              Веб-версия использует только технические cookies, необходимые для работы. Аналитика
              анонимизирована и не содержит персональных данных.
            </p>
          </section>

          <section>
            <h2 className="text-display mb-4 text-xl text-text-primary">5. Ваши права</h2>
            <p>
              Вы вправе запросить копию своих данных, их исправление или удаление. Напишите нам:{' '}
              <a href="mailto:support@plink.app" className="text-accent underline">
                support@plink.app
              </a>
            </p>
          </section>
        </div>
      </main>

      <footer className="border-t border-surface-2 py-8">
        <div className="container-main text-center text-sm text-[#B0B7B3]">
          © {new Date().getFullYear()} Plink. Все права защищены.
        </div>
      </footer>
    </>
  );
}
