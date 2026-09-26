Upload this folder as /_private/ in the web root ONLY if the FTP account cannot
reach the folder above the web root. Put bigcat.env (from .env.example, real
values) and a storage/ subfolder in it. The .htaccess denies all web access;
Nginx also returns 404 for /_private/. Prefer ../bigcat-private/ when possible.
Never commit bigcat.env.
